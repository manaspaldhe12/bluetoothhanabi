import XCTest
@testable import HanabiKit

final class HanabiEngineTests: XCTestCase {
    private func makePlayers(_ names: [String]) -> [(id: String, name: String)] {
        names.map { (id: $0, name: $0) }
    }

    // MARK: - Setup

    func testDealtHandSizesByPlayerCount() {
        for count in 2...5 {
            let players = makePlayers((0..<count).map { "p\($0)" })
            let game = HostGame(players: players, deck: Card.standardDeck().shuffled())
            let expected = count <= 3 ? 5 : 4
            for player in game.state.players {
                XCTAssertEqual(player.hand.count, expected)
            }
            XCTAssertEqual(game.state.drawPileCount, 50 - expected * count)
        }
    }

    func testStandardDeckHas50Cards() {
        let deck = Card.standardDeck()
        XCTAssertEqual(deck.count, 50)
        for color in CardColor.allCases {
            let cardsOfColor = deck.filter { $0.color == color }
            XCTAssertEqual(cardsOfColor.count, 10)
            XCTAssertEqual(cardsOfColor.filter { $0.number == 1 }.count, 3)
            XCTAssertEqual(cardsOfColor.filter { $0.number == 5 }.count, 1)
        }
    }

    // MARK: - Turn enforcement

    func testActionByWrongPlayerThrows() {
        let game = twoPlayerGame()
        XCTAssertThrowsError(try game.apply(.discard(handIndex: 0), by: "bob")) { error in
            XCTAssertEqual(error as? EngineError, .notYourTurn)
        }
    }

    func testInvalidHandIndexThrows() {
        let game = twoPlayerGame()
        XCTAssertThrowsError(try game.apply(.play(handIndex: 99), by: "alice")) { error in
            XCTAssertEqual(error as? EngineError, .invalidHandIndex)
        }
    }

    // MARK: - Playing cards

    func testSuccessfulPlayAdvancesStackAndTurn() throws {
        let deck = orderedDeckForDealing(aliceHand: [Card(color: .red, number: 1)], bobHand: [Card(color: .blue, number: 1)])
        let game = HostGame(players: makePlayers(["alice", "bob"]), deck: deck)

        try game.apply(.play(handIndex: 0), by: "alice")

        XCTAssertEqual(game.state.playedStacks[.red], 1)
        XCTAssertEqual(game.state.lives, GameState.maxLives)
        XCTAssertEqual(game.state.currentPlayer.id, "bob")
    }

    func testMisplayLosesALifeAndDiscardsCard() throws {
        let deck = orderedDeckForDealing(aliceHand: [Card(color: .red, number: 2)], bobHand: [Card(color: .blue, number: 1)])
        let game = HostGame(players: makePlayers(["alice", "bob"]), deck: deck)

        try game.apply(.play(handIndex: 0), by: "alice")

        XCTAssertEqual(game.state.playedStacks[.red], 0)
        XCTAssertEqual(game.state.lives, GameState.maxLives - 1)
        XCTAssertEqual(game.state.discardPile.count, 1)
        XCTAssertEqual(game.state.discardPile.first?.number, 2)
    }

    func testThreeMistakesEndsGameWithZeroScore() throws {
        let deck = orderedDeckForDealing(
            aliceHand: [Card(color: .red, number: 5), Card(color: .red, number: 5)],
            bobHand: [Card(color: .blue, number: 5), Card(color: .blue, number: 5)]
        )
        let game = HostGame(players: makePlayers(["alice", "bob"]), deck: deck)

        // Every play here is a guaranteed misplay (need 1, playing 5).
        try game.apply(.play(handIndex: 0), by: "alice") // life 3->2
        try game.apply(.play(handIndex: 0), by: "bob")   // life 2->1
        try game.apply(.play(handIndex: 0), by: "alice") // life 1->0, game over

        XCTAssertEqual(game.state.phase, .finished)
        XCTAssertEqual(game.state.finishReason, .outOfLives)
        XCTAssertEqual(game.state.score, 0)
    }

    /// Builds a fully deterministic 25-card play-through where alice and bob strictly
    /// alternate turns, each turn playing the next required card for some color's stack,
    /// until all 5 stacks reach 5 and the game ends as a perfect score.
    func testCompletingAllFiveStacksEndsGameAsPerfectScore() throws {
        let colors = CardColor.displayOrder
        var required: [Card] = []
        for number in 1...5 {
            for color in colors {
                required.append(Card(color: color, number: number))
            }
        }
        XCTAssertEqual(required.count, 25)

        // alice takes turns 0,2,4,...,24 (13 turns); bob takes 1,3,...,23 (12 turns).
        var aliceSeq: [Card] = []
        var bobSeq: [Card] = []
        for (index, card) in required.enumerated() {
            if index % 2 == 0 { aliceSeq.append(card) } else { bobSeq.append(card) }
        }
        XCTAssertEqual(aliceSeq.count, 13)
        XCTAssertEqual(bobSeq.count, 12)

        let aliceInitial = Array(aliceSeq[0..<5])
        let bobInitial = Array(bobSeq[0..<5])

        // alice draws after each of her first 12 plays (her 13th/final play ends the game
        // via the perfect-score shortcut and draws nothing); bob draws after all 12 of his
        // plays (none of his plays is the game's final one). Pad each list with filler cards
        // out to that exact count.
        var aliceDrawSlots = Array(aliceSeq[5...])
        while aliceDrawSlots.count < 12 { aliceDrawSlots.append(Card(color: .red, number: 1)) }
        var bobDrawSlots = Array(bobSeq[5...])
        while bobDrawSlots.count < 12 { bobDrawSlots.append(Card(color: .red, number: 1)) }

        // Chronological pop order: alice draw#1, bob draw#1, alice draw#2, bob draw#2, ...
        var popOrder: [Card] = []
        for i in 0..<12 {
            popOrder.append(aliceDrawSlots[i])
            popOrder.append(bobDrawSlots[i])
        }
        XCTAssertEqual(popOrder.count, 24)

        let dealTail = Self.dealTail(aliceInitial: aliceInitial, bobInitial: bobInitial)
        let fullDeck = popOrder.reversed() + dealTail

        let game = HostGame(players: makePlayers(["alice", "bob"]), deck: Array(fullDeck))

        var turns = 0
        while game.state.phase == .playing && turns < 30 {
            try game.apply(.play(handIndex: 0), by: game.state.currentPlayer.id)
            turns += 1
        }

        XCTAssertEqual(turns, 25)
        XCTAssertEqual(game.state.phase, .finished)
        XCTAssertEqual(game.state.finishReason, .perfectScore)
        XCTAssertEqual(game.state.score, 25)
    }

    func testCompletingAStackAwardsBonusHintToken() throws {
        // alice races red 1->5 on her turns; bob spends one hint (so a token is available to
        // refund) then plays yellow 1->3 on his remaining turns. Both hands are large enough
        // that neither player needs a drawn card within the turns we exercise.
        let aliceInitial = (1...5).map { Card(color: .red, number: $0) }
        let bobInitial = (1...5).map { Card(color: .yellow, number: $0) }
        let dealTail = Self.dealTail(aliceInitial: aliceInitial, bobInitial: bobInitial)
        let filler = (0..<12).map { _ in Card(color: .blue, number: 1) }
        let game = HostGame(players: makePlayers(["alice", "bob"]), deck: filler + dealTail)

        try game.apply(.play(handIndex: 0), by: "alice")   // red 1
        try game.apply(.hint(targetPlayerId: "alice", type: .color(.red)), by: "bob") // spends a token: 8->7
        try game.apply(.play(handIndex: 0), by: "alice")   // red 2
        try game.apply(.play(handIndex: 0), by: "bob")     // yellow 1
        try game.apply(.play(handIndex: 0), by: "alice")   // red 3
        try game.apply(.play(handIndex: 0), by: "bob")     // yellow 2
        try game.apply(.play(handIndex: 0), by: "alice")   // red 4
        try game.apply(.play(handIndex: 0), by: "bob")     // yellow 3

        XCTAssertEqual(game.state.hintTokens, GameState.maxHintTokens - 1)

        try game.apply(.play(handIndex: 0), by: "alice")   // red 5, completes the red stack

        XCTAssertEqual(game.state.playedStacks[.red], 5)
        XCTAssertEqual(game.state.hintTokens, GameState.maxHintTokens, "completing a stack should refund a hint token")
        XCTAssertEqual(game.state.phase, .playing, "only one of five stacks is complete")
    }

    // MARK: - Discarding

    func testDiscardReturnsHintTokenUpToMax() throws {
        let deck = orderedDeckForDealing(aliceHand: [Card(color: .red, number: 3)], bobHand: [Card(color: .blue, number: 1)])
        let game = HostGame(players: makePlayers(["alice", "bob"]), deck: deck)

        try game.apply(.hint(targetPlayerId: "bob", type: .color(.blue)), by: "alice")
        XCTAssertEqual(game.state.hintTokens, GameState.maxHintTokens - 1)

        try game.apply(.discard(handIndex: 0), by: "bob")
        XCTAssertEqual(game.state.hintTokens, GameState.maxHintTokens)
    }

    func testCannotDiscardAtMaxHintTokens() {
        let game = twoPlayerGame()
        XCTAssertEqual(game.state.hintTokens, GameState.maxHintTokens)
        XCTAssertThrowsError(try game.apply(.discard(handIndex: 0), by: "alice")) { error in
            XCTAssertEqual(error as? EngineError, .cannotDiscardAtMaxHintTokens)
        }
    }

    // MARK: - Hints

    func testHintTouchesOnlyMatchingCardsAndSetsExclusions() throws {
        // Turns start with alice, so she must be the hinter here; the dealing algorithm also
        // requires alice's card count >= bob's (target) count, so alice gets a same-size dummy hand.
        let deck = orderedDeckForDealing(
            aliceHand: [Card(color: .white, number: 4), Card(color: .green, number: 5)],
            bobHand: [Card(color: .red, number: 2), Card(color: .blue, number: 3)]
        )
        let game = HostGame(players: makePlayers(["alice", "bob"]), deck: deck)

        try game.apply(.hint(targetPlayerId: "bob", type: .color(.red)), by: "alice")

        let bob = game.state.player(withId: "bob")!
        XCTAssertEqual(bob.hand[0].knowledge.knownColor, .red)
        XCTAssertNil(bob.hand[1].knowledge.knownColor)
        XCTAssertTrue(bob.hand[1].knowledge.excludedColors.contains(.red))
    }

    func testHintWithNoMatchesThrows() {
        let deck = orderedDeckForDealing(
            aliceHand: [Card(color: .red, number: 1)],
            bobHand: [Card(color: .blue, number: 2)]
        )
        let game = HostGame(players: makePlayers(["alice", "bob"]), deck: deck)

        XCTAssertThrowsError(try game.apply(.hint(targetPlayerId: "bob", type: .color(.red)), by: "alice")) { error in
            XCTAssertEqual(error as? EngineError, .hintMustMatchAtLeastOneCard)
        }
    }

    func testCannotHintSelf() {
        let game = twoPlayerGame()
        XCTAssertThrowsError(try game.apply(.hint(targetPlayerId: "alice", type: .number(1)), by: "alice")) { error in
            XCTAssertEqual(error as? EngineError, .cannotTargetSelfWithHint)
        }
    }

    func testNoHintTokensThrows() throws {
        let deck = orderedDeckForDealing(
            aliceHand: Array(repeating: Card(color: .red, number: 1), count: 5),
            bobHand: Array(repeating: Card(color: .blue, number: 2), count: 5)
        )
        let game = HostGame(players: makePlayers(["alice", "bob"]), deck: deck)

        for _ in 0..<(GameState.maxHintTokens / 2) {
            try game.apply(.hint(targetPlayerId: "bob", type: .color(.blue)), by: "alice")
            try game.apply(.hint(targetPlayerId: "alice", type: .color(.red)), by: "bob")
        }

        XCTAssertEqual(game.state.hintTokens, 0)
        XCTAssertThrowsError(try game.apply(.hint(targetPlayerId: "bob", type: .color(.blue)), by: "alice")) { error in
            XCTAssertEqual(error as? EngineError, .noHintTokensAvailable)
        }
    }

    // MARK: - Finished-game guard

    func testActionsAfterGameEndsThrowGameAlreadyFinished() throws {
        let deck = orderedDeckForDealing(
            aliceHand: [Card(color: .red, number: 5), Card(color: .red, number: 5)],
            bobHand: [Card(color: .blue, number: 5), Card(color: .blue, number: 5)]
        )
        let game = HostGame(players: makePlayers(["alice", "bob"]), deck: deck)
        try game.apply(.play(handIndex: 0), by: "alice")
        try game.apply(.play(handIndex: 0), by: "bob")
        try game.apply(.play(handIndex: 0), by: "alice") // 0 lives, game over
        XCTAssertEqual(game.state.phase, .finished)

        for action: GameAction in [.play(handIndex: 0), .discard(handIndex: 0), .hint(targetPlayerId: "bob", type: .number(1))] {
            XCTAssertThrowsError(try game.apply(action, by: game.state.players[0].id)) { error in
                XCTAssertEqual(error as? EngineError, .gameAlreadyFinished)
            }
        }
    }

    // MARK: - More invalid-input guards

    func testDiscardInvalidHandIndexThrows() throws {
        // Discard is blocked at max hint tokens (a fresh game's starting state), so spend one
        // first (via a guaranteed-to-match hint) to make sure invalidHandIndex — not
        // cannotDiscardAtMaxHintTokens — is what's actually being exercised.
        let deck = orderedDeckForDealing(aliceHand: [Card(color: .red, number: 1)], bobHand: [Card(color: .blue, number: 1)])
        let game = HostGame(players: makePlayers(["alice", "bob"]), deck: deck)
        try game.apply(.hint(targetPlayerId: "bob", type: .color(.blue)), by: "alice")

        XCTAssertThrowsError(try game.apply(.discard(handIndex: 99), by: "bob")) { error in
            XCTAssertEqual(error as? EngineError, .invalidHandIndex)
        }
    }

    func testHintUnknownTargetPlayerThrows() {
        let game = twoPlayerGame()
        XCTAssertThrowsError(try game.apply(.hint(targetPlayerId: "carol", type: .number(1)), by: "alice")) { error in
            XCTAssertEqual(error as? EngineError, .unknownTargetPlayer)
        }
    }

    // MARK: - Score edge cases

    func testScoreForcedToZeroEvenIfStacksWerePlayedBeforeThirdMistake() throws {
        // alice successfully plays red 1 and red 2 (raising the score to 2), then the team
        // takes three guaranteed misplays. The official rule is score = 0 on a third mistake
        // regardless of what was played beforehand. Equal-size hands (round-robin dealing can't
        // give one player 2+ more cards than the other — see orderedDeckForDealing's docs) plus
        // generous filler (so the deck doesn't run dry and end the game early via deckExhausted
        // before these 5 turns complete).
        let aliceInitial = [Card(color: .red, number: 1), Card(color: .red, number: 2), Card(color: .red, number: 5)]
        let bobInitial = [Card(color: .blue, number: 5), Card(color: .blue, number: 5), Card(color: .blue, number: 1)]
        let filler = (0..<12).map { _ in Card(color: .white, number: 1) }
        let deck = orderedDeckForDealing(aliceHand: aliceInitial, bobHand: bobInitial, filler: filler)
        let game = HostGame(players: makePlayers(["alice", "bob"]), deck: deck)

        try game.apply(.play(handIndex: 0), by: "alice") // red 1: success
        try game.apply(.play(handIndex: 0), by: "bob")   // blue5, needed=1: misplay, life 3->2
        try game.apply(.play(handIndex: 0), by: "alice") // red 2: success, score now 2
        try game.apply(.play(handIndex: 0), by: "bob")   // blue5 (2nd), needed still 1: misplay, life 2->1
        try game.apply(.play(handIndex: 0), by: "alice") // red 5, needed=3: misplay, life 1->0

        XCTAssertEqual(game.state.playedStacks[.red], 2, "the two successful plays still happened")
        XCTAssertEqual(game.state.phase, .finished)
        XCTAssertEqual(game.state.finishReason, .outOfLives)
        XCTAssertEqual(game.state.score, 0, "official rule: 3 mistakes forces score to 0 regardless of stacks played")
    }

    func testBonusTokenNotAwardedBeyondMax() throws {
        // Same red-race setup as testCompletingAStackAwardsBonusHintToken, but bob never
        // spends a hint, so tokens are already at max when red completes.
        let aliceInitial = (1...5).map { Card(color: .red, number: $0) }
        let bobInitial = (1...5).map { Card(color: .yellow, number: $0) }
        let dealTail = Self.dealTail(aliceInitial: aliceInitial, bobInitial: bobInitial)
        let filler = (0..<12).map { _ in Card(color: .blue, number: 1) }
        let game = HostGame(players: makePlayers(["alice", "bob"]), deck: filler + dealTail)
        XCTAssertEqual(game.state.hintTokens, GameState.maxHintTokens)

        for _ in 0..<4 {
            try game.apply(.play(handIndex: 0), by: "alice")
            try game.apply(.play(handIndex: 0), by: "bob")
        }
        try game.apply(.play(handIndex: 0), by: "alice") // red 5, completes the stack

        XCTAssertEqual(game.state.playedStacks[.red], 5)
        XCTAssertEqual(game.state.hintTokens, GameState.maxHintTokens, "already at max — nothing to refund")
    }

    // MARK: - Player lookups

    func testPlayerLookupsReturnNilForUnknownId() {
        let game = twoPlayerGame()
        XCTAssertNil(game.state.player(withId: "carol"))
        XCTAssertNil(game.state.playerIndex(withId: "carol"))
        XCTAssertNotNil(game.state.player(withId: "alice"))
        XCTAssertEqual(game.state.playerIndex(withId: "bob"), 1)
    }

    // MARK: - Hand size helper

    func testHandSizeHelperBoundaries() {
        XCTAssertEqual(GameState.handSize(forPlayerCount: 2), 5)
        XCTAssertEqual(GameState.handSize(forPlayerCount: 3), 5)
        XCTAssertEqual(GameState.handSize(forPlayerCount: 4), 4)
        XCTAssertEqual(GameState.handSize(forPlayerCount: 5), 4)
    }

    // MARK: - Lobby boundaries

    func testLobbyCanStartBoundaries() {
        func lobby(_ count: Int) -> LobbyState {
            LobbyState(players: (0..<count).map { LobbyPlayer(id: "p\($0)", name: "P\($0)", isHost: $0 == 0) })
        }
        XCTAssertFalse(lobby(1).canStart, "below minimum")
        XCTAssertTrue(lobby(LobbyState.minPlayers).canStart)
        XCTAssertTrue(lobby(LobbyState.maxPlayers).canStart)
        XCTAssertFalse(lobby(LobbyState.maxPlayers + 1).canStart, "above maximum")
    }

    // MARK: - CardKnowledge narrowing, independent of the engine

    func testCardKnowledgeNarrowsPossibleValuesAcrossMultipleHints() {
        var knowledge = CardKnowledge()
        XCTAssertEqual(knowledge.possibleColors, Set(CardColor.allCases))
        XCTAssertEqual(knowledge.possibleNumbers, Set(1...5))

        knowledge.apply(colorHint: .red, matched: false)
        knowledge.apply(colorHint: .blue, matched: false)
        XCTAssertEqual(knowledge.possibleColors, Set(CardColor.allCases).subtracting([.red, .blue]))
        XCTAssertNil(knowledge.knownColor, "still ambiguous among the 3 remaining colors")

        knowledge.apply(numberHint: 3, matched: true)
        XCTAssertEqual(knowledge.knownNumber, 3)
        XCTAssertEqual(knowledge.possibleNumbers, [3])

        knowledge.apply(colorHint: .green, matched: true)
        XCTAssertEqual(knowledge.knownColor, .green)
        XCTAssertEqual(knowledge.possibleColors, [.green])
    }

    // MARK: - Multi-player turn rotation (3-5 players)

    func testTurnOrderRotatesThroughAllPlayersAndWrapsAround() throws {
        for playerCount in 3...5 {
            let ids = (0..<playerCount).map { "p\($0)" }
            let colors = Array(CardColor.displayOrder.prefix(playerCount))
            // Player i's hand: their assigned color's 1, then that color's 2 — two guaranteed
            // successful plays each, enough to observe two full laps around the table.
            let hands = colors.map { color in [Card(color: color, number: 1), Card(color: color, number: 2)] }
            let filler = (0..<20).map { _ in Card(color: .white, number: 1) }
            let deck = orderedDeckForNPlayerDealing(hands: hands, filler: filler)
            let game = HostGame(players: makePlayers(ids), deck: deck)

            var observedOrder: [String] = []
            for _ in 0..<(playerCount * 2) {
                observedOrder.append(game.state.currentPlayer.id)
                try game.apply(.play(handIndex: 0), by: game.state.currentPlayer.id)
            }

            XCTAssertEqual(observedOrder, ids + ids, "turn order for \(playerCount) players should visit everyone in order, twice")
            for (index, color) in colors.enumerated() {
                XCTAssertEqual(game.state.playedStacks[color], 2, "player \(index)'s color should have advanced to 2 via two successful plays")
            }
            XCTAssertEqual(game.state.lives, GameState.maxLives, "every play in this scenario was a guaranteed success")
        }
    }

    // MARK: - Deck exhaustion / final round

    func testDeckExhaustionTriggersFinalRoundThenEndsGame() throws {
        // Plays (not discards, which are blocked at max hint tokens) that each succeed, so no
        // stray life loss or token-gating interferes with observing the final-round countdown.
        let aliceHand = [Card(color: .blue, number: 1), Card(color: .blue, number: 2)]
        let bobHand = [Card(color: .red, number: 1)]
        let deck = orderedDeckForDealing(aliceHand: aliceHand, bobHand: bobHand, filler: [])
        let game = HostGame(players: makePlayers(["alice", "bob"]), deck: deck)

        XCTAssertEqual(game.state.drawPileCount, 0)

        // The turn that discovers the pile is empty starts the countdown but must not also
        // count toward it, or the triggering player loses their own final turn.
        try game.apply(.play(handIndex: 0), by: "alice") // blue 1
        XCTAssertEqual(game.state.finalRoundTurnsRemaining, 2)
        XCTAssertEqual(game.state.phase, .playing)

        try game.apply(.play(handIndex: 0), by: "bob") // red 1
        XCTAssertEqual(game.state.finalRoundTurnsRemaining, 1)
        XCTAssertEqual(game.state.phase, .playing)

        try game.apply(.play(handIndex: 0), by: "alice") // blue 2
        XCTAssertEqual(game.state.phase, .finished)
        XCTAssertEqual(game.state.finishReason, .deckExhausted)
    }

    // MARK: - Helpers

    private func twoPlayerGame() -> HostGame {
        HostGame(players: makePlayers(["alice", "bob"]), deck: Card.standardDeck().shuffled())
    }

    /// The last 10 cards of a deck passed to `HostGame.init`, ordered so that standard
    /// round-robin dealing (5 rounds, alice then bob, drawn via `popLast()`) produces exactly
    /// `aliceInitial`/`bobInitial` as each player's starting hand, in order.
    private static func dealTail(aliceInitial: [Card], bobInitial: [Card]) -> [Card] {
        precondition(aliceInitial.count == 5 && bobInitial.count == 5)
        var dealOrder: [Card] = []
        for i in 0..<5 {
            dealOrder.append(aliceInitial[i])
            dealOrder.append(bobInitial[i])
        }
        return Array(dealOrder.reversed())
    }

    /// Builds a deck ordered so that, once dealt round-robin from the top, alice and bob end
    /// up with exactly the given hands (in hand order, index 0 first). Any remaining cards are
    /// appended as filler for subsequent draws, unless `filler` is supplied explicitly (pass
    /// `[]` to leave the draw pile empty after the initial deal — but note that starves the
    /// game of the finalRoundTurnsRemaining countdown almost immediately; use generous filler
    /// for any test that needs more than ~2 turns per player). Hands shorter than the
    /// player-count-derived hand size simply deal out early, leaving the rest of that round's
    /// slots unfilled — fine for tests that only touch the cards actually provided. Real dealing
    /// pops alice's card then bob's card *every* round regardless of who's "supposed" to be
    /// done, so alice can end up at most 1 card ahead of bob — never 2+ — no matter how the
    /// requested hand sizes differ; `aliceHand.count - bobHand.count` must be 0 or 1.
    private func orderedDeckForDealing(aliceHand: [Card], bobHand: [Card], filler: [Card]? = nil) -> [Card] {
        precondition(aliceHand.count >= bobHand.count)
        precondition(aliceHand.count - bobHand.count <= 1, "round-robin dealing can't produce a gap of 2+ cards")
        var dealOrder: [Card] = []
        for i in 0..<aliceHand.count {
            dealOrder.append(aliceHand[i])
            if i < bobHand.count {
                dealOrder.append(bobHand[i])
            }
        }
        var deck = filler ?? []
        deck.append(contentsOf: dealOrder.reversed())
        return deck
    }

    /// General N-player analog of `orderedDeckForDealing`: `hands[i]` is player i's hand (all
    /// the same length), dealt round-robin in player order. Pass generous `filler` for any test
    /// needing more than ~1 turn per player, or the draw pile empties immediately and the
    /// finalRoundTurnsRemaining countdown ends the game a few turns later than expected.
    private func orderedDeckForNPlayerDealing(hands: [[Card]], filler: [Card] = []) -> [Card] {
        precondition(!hands.isEmpty)
        let handSize = hands[0].count
        precondition(hands.allSatisfy { $0.count == handSize })
        var dealOrder: [Card] = []
        for round in 0..<handSize {
            for hand in hands {
                dealOrder.append(hand[round])
            }
        }
        var deck = filler
        deck.append(contentsOf: dealOrder.reversed())
        return deck
    }
}
