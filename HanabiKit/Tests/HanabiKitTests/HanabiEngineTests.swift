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
    /// `[]` to leave the draw pile empty after the initial deal). Hands shorter than the
    /// player-count-derived hand size simply deal out early, leaving the rest of that round's
    /// slots unfilled — fine for tests that only touch the cards actually provided.
    private func orderedDeckForDealing(aliceHand: [Card], bobHand: [Card], filler: [Card]? = nil) -> [Card] {
        // Real dealing pops alice's card then bob's card each round; since alice always goes
        // first, she can never end up with fewer cards than bob.
        precondition(aliceHand.count >= bobHand.count)
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
}
