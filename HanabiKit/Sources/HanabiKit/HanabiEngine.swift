import Foundation

/// Owns the authoritative game state for a match. Only the host runs a `HostGame`; every
/// other peer just renders the `GameState` snapshots the host broadcasts. The draw pile is
/// kept here, off the wire, so no client ever receives card identities it isn't supposed
/// to know yet.
public final class HostGame {
    public private(set) var state: GameState
    private var drawPile: [Card]

    public init(players: [(id: String, name: String)], deck: [Card] = Card.standardDeck().shuffled()) {
        precondition(players.count >= 2 && players.count <= 5, "Hanabi supports 2-5 players")
        var pile = deck
        let handSize = GameState.handSize(forPlayerCount: players.count)

        var dealtPlayers: [PlayerState] = players.map { PlayerState(id: $0.id, name: $0.name) }
        for _ in 0..<handSize {
            for playerIndex in dealtPlayers.indices {
                guard let card = pile.popLast() else { break }
                dealtPlayers[playerIndex].hand.append(HandCard(card: card))
            }
        }

        self.drawPile = pile
        self.state = GameState(
            players: dealtPlayers,
            currentPlayerIndex: 0,
            drawPileCount: pile.count,
            playedStacks: Dictionary(uniqueKeysWithValues: CardColor.allCases.map { ($0, 0) })
        )
        self.state.appendLog("Game started with \(players.count) players.")
    }

    @discardableResult
    public func apply(_ action: GameAction, by playerId: String) throws -> ActionOutcome {
        guard state.phase == .playing else { throw EngineError.gameAlreadyFinished }
        guard state.currentPlayer.id == playerId else { throw EngineError.notYourTurn }

        switch action {
        case .play(let handIndex):
            return try applyPlay(handIndex: handIndex, playerId: playerId)
        case .discard(let handIndex):
            return try applyDiscard(handIndex: handIndex, playerId: playerId)
        case .hint(let targetId, let type):
            return try applyHint(targetPlayerId: targetId, type: type, by: playerId)
        }
    }

    private func applyPlay(handIndex: Int, playerId: String) throws -> ActionOutcome {
        let playerIdx = state.playerIndex(withId: playerId)!
        guard state.players[playerIdx].hand.indices.contains(handIndex) else {
            throw EngineError.invalidHandIndex
        }

        let handCard = state.players[playerIdx].hand.remove(at: handIndex)
        let card = handCard.card
        let needed = (state.playedStacks[card.color] ?? 0) + 1
        let playerName = state.players[playerIdx].name
        let wasMistake: Bool
        let description: String

        if card.number == needed {
            state.playedStacks[card.color] = needed
            wasMistake = false
            description = "\(playerName) played \(card.color.rawValue.capitalized) \(card.number)."
            if needed == 5 && state.hintTokens < GameState.maxHintTokens {
                state.hintTokens += 1
            }
        } else {
            state.discardPile.append(card)
            state.lives -= 1
            wasMistake = true
            description = "\(playerName) misplayed \(card.color.rawValue.capitalized) \(card.number)! (\(state.lives) lives left)"
        }

        state.appendLog(description)

        if state.lives <= 0 {
            finishGame(reason: .outOfLives)
            return ActionOutcome(description: description, wasMistake: wasMistake)
        }

        if state.playedStacks.values.reduce(0, +) == 25 {
            finishGame(reason: .perfectScore)
            return ActionOutcome(description: description, wasMistake: wasMistake)
        }

        let justEmptied = drawReplacementCard(forPlayerAt: playerIdx)
        advanceTurn(skipFinalRoundDecrement: justEmptied)
        return ActionOutcome(description: description, wasMistake: wasMistake)
    }

    private func applyDiscard(handIndex: Int, playerId: String) throws -> ActionOutcome {
        guard state.hintTokens < GameState.maxHintTokens else {
            throw EngineError.cannotDiscardAtMaxHintTokens
        }
        let playerIdx = state.playerIndex(withId: playerId)!
        guard state.players[playerIdx].hand.indices.contains(handIndex) else {
            throw EngineError.invalidHandIndex
        }

        let handCard = state.players[playerIdx].hand.remove(at: handIndex)
        state.discardPile.append(handCard.card)
        state.hintTokens = min(GameState.maxHintTokens, state.hintTokens + 1)

        let playerName = state.players[playerIdx].name
        let description = "\(playerName) discarded \(handCard.card.color.rawValue.capitalized) \(handCard.card.number)."
        state.appendLog(description)

        let justEmptied = drawReplacementCard(forPlayerAt: playerIdx)
        advanceTurn(skipFinalRoundDecrement: justEmptied)
        return ActionOutcome(description: description, wasMistake: false)
    }

    private func applyHint(targetPlayerId: String, type: HintType, by playerId: String) throws -> ActionOutcome {
        guard state.hintTokens > 0 else { throw EngineError.noHintTokensAvailable }
        guard targetPlayerId != playerId else { throw EngineError.cannotTargetSelfWithHint }
        guard let targetIdx = state.playerIndex(withId: targetPlayerId) else {
            throw EngineError.unknownTargetPlayer
        }

        var matchedAny = false
        for cardIdx in state.players[targetIdx].hand.indices {
            let card = state.players[targetIdx].hand[cardIdx].card
            switch type {
            case .color(let color):
                let matched = card.color == color
                matchedAny = matchedAny || matched
                state.players[targetIdx].hand[cardIdx].knowledge.apply(colorHint: color, matched: matched)
            case .number(let number):
                let matched = card.number == number
                matchedAny = matchedAny || matched
                state.players[targetIdx].hand[cardIdx].knowledge.apply(numberHint: number, matched: matched)
            }
        }

        guard matchedAny else { throw EngineError.hintMustMatchAtLeastOneCard }

        state.hintTokens -= 1
        let fromName = state.currentPlayer.name
        let toName = state.players[targetIdx].name
        let hintDescription: String
        switch type {
        case .color(let color): hintDescription = "\(fromName) told \(toName) about \(color.rawValue) cards."
        case .number(let number): hintDescription = "\(fromName) told \(toName) about \(number)s."
        }
        state.appendLog(hintDescription)

        advanceTurn()
        return ActionOutcome(description: hintDescription, wasMistake: false)
    }

    /// Draws a replacement card for the given player. Returns `true` if this call is the one
    /// that discovered the draw pile is now empty (i.e. it just started the final round) — in
    /// that case the triggering turn must NOT also count toward the final-round countdown, or
    /// the last player to draw would be shortchanged one of their remaining turns.
    @discardableResult
    private func drawReplacementCard(forPlayerAt playerIdx: Int) -> Bool {
        guard let card = drawPile.popLast() else {
            let justEmptied = state.finalRoundTurnsRemaining == nil
            if justEmptied {
                state.finalRoundTurnsRemaining = state.players.count
            }
            state.drawPileCount = 0
            return justEmptied
        }
        state.players[playerIdx].hand.append(HandCard(card: card))
        state.drawPileCount = drawPile.count
        if drawPile.isEmpty && state.finalRoundTurnsRemaining == nil {
            state.finalRoundTurnsRemaining = state.players.count
            return true
        }
        return false
    }

    private func advanceTurn(skipFinalRoundDecrement: Bool = false) {
        guard state.phase == .playing else { return }

        if let remaining = state.finalRoundTurnsRemaining, !skipFinalRoundDecrement {
            let newRemaining = remaining - 1
            state.finalRoundTurnsRemaining = newRemaining
            if newRemaining <= 0 {
                finishGame(reason: .deckExhausted)
                return
            }
        }
        state.currentPlayerIndex = (state.currentPlayerIndex + 1) % state.players.count
    }

    private func finishGame(reason: FinishReason) {
        state.phase = .finished
        state.finishReason = reason
        switch reason {
        case .perfectScore:
            state.appendLog("Perfect score! The team scored 25.")
        case .outOfLives:
            state.appendLog("Out of lives! Final score: 0.")
        case .deckExhausted:
            state.appendLog("Deck exhausted. Final score: \(state.score).")
        }
    }
}
