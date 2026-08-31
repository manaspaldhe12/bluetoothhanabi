import XCTest
@testable import HanabiKit

/// Every case of `NetworkMessage` travels over the wire as JSON (MultipeerManager just calls
/// `encoded()`/`decode(_:)`) — a bug in any case's Codable synthesis would silently break that
/// specific message type in a way no UI-level test would catch. These verify every case
/// round-trips byte-for-byte-equivalent.
final class NetworkMessageTests: XCTestCase {
    private func assertRoundTrips(_ message: NetworkMessage, file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try message.encoded()
        let decoded = try NetworkMessage.decode(data)
        XCTAssertEqual(decoded, message, file: file, line: line)
    }

    func testJoinRequestRoundTrips() throws {
        try assertRoundTrips(.joinRequest(name: "Alice"))
    }

    func testLobbyUpdateRoundTrips() throws {
        let lobby = LobbyState(players: [
            LobbyPlayer(id: "a", name: "Alice", isHost: true),
            LobbyPlayer(id: "b", name: "Bob", isHost: false),
        ])
        try assertRoundTrips(.lobbyUpdate(lobby))
    }

    func testGameStartedAndGameStateUpdateRoundTrip() throws {
        let game = HostGame(
            players: [(id: "a", name: "Alice"), (id: "b", name: "Bob")],
            deck: Card.standardDeck().shuffled()
        )
        try assertRoundTrips(.gameStarted(game.state))
        try assertRoundTrips(.gameStateUpdate(game.state))
    }

    func testActionRoundTripsForEveryCase() throws {
        try assertRoundTrips(.action(.play(handIndex: 2)))
        try assertRoundTrips(.action(.discard(handIndex: 0)))
        try assertRoundTrips(.action(.hint(targetPlayerId: "bob", type: .color(.red))))
        try assertRoundTrips(.action(.hint(targetPlayerId: "bob", type: .number(3))))
    }

    func testActionRejectedRoundTrips() throws {
        try assertRoundTrips(.actionRejected(reason: "It's not your turn."))
    }

    func testReturnedToLobbyRoundTrips() throws {
        let lobby = LobbyState(players: [LobbyPlayer(id: "a", name: "Alice", isHost: true)])
        try assertRoundTrips(.returnedToLobby(lobby))
    }

    func testDecodingGarbageDataThrows() {
        XCTAssertThrowsError(try NetworkMessage.decode(Data([0xFF, 0x00, 0x01])))
    }

    /// A GameState round-trip should preserve knowledge (positive AND excluded) exactly — the
    /// whole point of hints is deducing information from what's excluded, not just what's known.
    func testGameStateRoundTripPreservesCardKnowledgeExclusions() throws {
        let game = HostGame(
            players: [(id: "alice", name: "Alice"), (id: "bob", name: "Bob")],
            deck: Card.standardDeck().shuffled()
        )
        try game.apply(.hint(targetPlayerId: "bob", type: .color(game.state.players[1].hand[0].card.color)), by: "alice")

        let data = try NetworkMessage.gameStateUpdate(game.state).encoded()
        guard case .gameStateUpdate(let decodedState) = try NetworkMessage.decode(data) else {
            return XCTFail("expected a gameStateUpdate")
        }

        let originalBob = game.state.players[1]
        let decodedBob = decodedState.players[1]
        XCTAssertEqual(decodedBob.hand.map(\.knowledge), originalBob.hand.map(\.knowledge))
    }
}
