import XCTest
import MultipeerConnectivity
import HanabiKit
@testable import BluetoothHanabi

/// Exercises GameViewModel's network-message handling and turn-application logic by calling
/// `manager.onReceiveMessage?`/`manager.onPeerDisconnected?` directly — the same closures a
/// real MultipeerManager would invoke — rather than ever starting real hosting/browsing. See
/// MultipeerManagerTests for why: no Bluetooth in CI runners, and Bonjour discovery between
/// two runner processes isn't reliable enough to build a test on.
@MainActor
final class GameViewModelTests: XCTestCase {
    // MARK: - Lobby sync (client side)

    func testJoinerAdoptsLobbyUpdateAndEntersLobby() {
        let vm = GameViewModel(playerName: "Alice")
        vm.isHost = false
        let hostPeer = MCPeerID(displayName: "Host#0000")
        let newLobby = LobbyState(players: [
            LobbyPlayer(id: hostPeer.displayName, name: "Host", isHost: true),
            LobbyPlayer(id: vm.localPlayerId, name: "Alice", isHost: false),
        ])

        vm.manager.onReceiveMessage?(.lobbyUpdate(newLobby), hostPeer)

        XCTAssertEqual(vm.phase, .lobby)
        XCTAssertEqual(vm.lobby.players.count, 2)
    }

    func testHostIgnoresIncomingLobbyUpdate() {
        // The host is the sole authority on lobby membership; it must not adopt a lobbyUpdate
        // arriving from someone else (e.g. an echo, or a confused/stale peer).
        let vm = GameViewModel(playerName: "Alice")
        vm.isHost = true
        vm.lobby = LobbyState(players: [LobbyPlayer(id: vm.localPlayerId, name: "Alice", isHost: true)])
        let otherPeer = MCPeerID(displayName: "Bob#0000")
        let bogusLobby = LobbyState(players: [LobbyPlayer(id: "nonsense", name: "Ghost", isHost: true)])

        vm.manager.onReceiveMessage?(.lobbyUpdate(bogusLobby), otherPeer)

        XCTAssertEqual(vm.lobby.players.count, 1)
        XCTAssertEqual(vm.lobby.players.first?.id, vm.localPlayerId)
    }

    // MARK: - Join requests (host side)

    func testHostAddsNewJoinerToLobby() {
        let vm = GameViewModel(playerName: "Alice")
        vm.isHost = true
        vm.lobby = LobbyState(players: [LobbyPlayer(id: vm.localPlayerId, name: "Alice", isHost: true)])
        let bobPeer = MCPeerID(displayName: "Bob#0000")

        vm.manager.onReceiveMessage?(.joinRequest(name: "Bob"), bobPeer)

        XCTAssertEqual(vm.lobby.players.count, 2)
        XCTAssertTrue(vm.lobby.players.contains { $0.id == bobPeer.displayName && $0.name == "Bob" })
    }

    func testHostDoesNotDuplicateAnAlreadyJoinedPlayer() {
        let vm = GameViewModel(playerName: "Alice")
        vm.isHost = true
        let bobPeer = MCPeerID(displayName: "Bob#0000")
        vm.lobby = LobbyState(players: [
            LobbyPlayer(id: vm.localPlayerId, name: "Alice", isHost: true),
            LobbyPlayer(id: bobPeer.displayName, name: "Bob", isHost: false),
        ])

        vm.manager.onReceiveMessage?(.joinRequest(name: "Bob"), bobPeer)

        XCTAssertEqual(vm.lobby.players.count, 2)
    }

    func testHostRejectsJoinRequestWhenLobbyIsFull() {
        let vm = GameViewModel(playerName: "Alice")
        vm.isHost = true
        vm.lobby = LobbyState(players: (0..<LobbyState.maxPlayers).map {
            LobbyPlayer(id: "p\($0)", name: "P\($0)", isHost: $0 == 0)
        })
        let newPeer = MCPeerID(displayName: "Newcomer#0000")

        vm.manager.onReceiveMessage?(.joinRequest(name: "Newcomer"), newPeer)

        XCTAssertEqual(vm.lobby.players.count, LobbyState.maxPlayers)
        XCTAssertFalse(vm.lobby.players.contains { $0.id == newPeer.displayName })
    }

    // MARK: - Game state sync (client side)

    func testJoinerAdoptsGameStateOnGameStarted() {
        let vm = GameViewModel(playerName: "Alice")
        vm.isHost = false
        let hostPeer = MCPeerID(displayName: "Host#0000")
        let engine = HostGame(players: [
            (id: hostPeer.displayName, name: "Host"),
            (id: vm.localPlayerId, name: "Alice"),
        ])

        vm.manager.onReceiveMessage?(.gameStarted(engine.state), hostPeer)

        XCTAssertEqual(vm.phase, .game)
        XCTAssertEqual(vm.gameState?.players.count, 2)
    }

    // MARK: - Actions arriving at the host

    func testHostAppliesValidRemoteActionAndAdvancesTurn() {
        let vm = GameViewModel(playerName: "Alice")
        vm.isHost = true
        let bobPeer = MCPeerID(displayName: "Bob#0000")
        // Deal bob first so this is legitimately his turn without needing any setup moves.
        let engine = HostGame(players: [
            (id: bobPeer.displayName, name: "Bob"),
            (id: vm.localPlayerId, name: "Alice"),
        ])
        vm.hostGame = engine
        vm.gameState = engine.state
        XCTAssertEqual(engine.state.currentPlayer.id, bobPeer.displayName)

        vm.manager.onReceiveMessage?(.action(.play(handIndex: 0)), bobPeer)

        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.gameState?.currentPlayer.id, vm.localPlayerId, "turn should have advanced to alice")
        XCTAssertFalse(vm.gameState?.log.isEmpty ?? true)
    }

    func testHostSilentlyDropsRemoteActionSentOutOfTurn() {
        let vm = GameViewModel(playerName: "Alice")
        vm.isHost = true
        let bobPeer = MCPeerID(displayName: "Bob#0000")
        // Default player order means Alice goes first, so this action from Bob is illegal.
        let engine = HostGame(players: [
            (id: vm.localPlayerId, name: "Alice"),
            (id: bobPeer.displayName, name: "Bob"),
        ])
        vm.hostGame = engine
        vm.gameState = engine.state
        XCTAssertEqual(engine.state.currentPlayer.id, vm.localPlayerId)

        vm.manager.onReceiveMessage?(.action(.play(handIndex: 0)), bobPeer)

        // The rejection is only meant to reach the offending remote peer (over the network),
        // never surfaced as the host's own errorMessage, and the game state must be untouched.
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.gameState?.currentPlayer.id, vm.localPlayerId)
    }

    func testNonHostIgnoresIncomingActionMessages() {
        // A client should never apply a GameAction locally — only the host does that.
        let vm = GameViewModel(playerName: "Alice")
        vm.isHost = false
        let hostPeer = MCPeerID(displayName: "Host#0000")
        let engine = HostGame(players: [
            (id: hostPeer.displayName, name: "Host"),
            (id: vm.localPlayerId, name: "Alice"),
        ])
        vm.gameState = engine.state

        vm.manager.onReceiveMessage?(.action(.play(handIndex: 0)), hostPeer)

        // Untouched: vm.hostGame is nil for a client, so nothing should have thrown or mutated.
        XCTAssertEqual(vm.gameState?.currentPlayer.id, engine.state.currentPlayer.id)
    }

    // MARK: - Errors and disconnection

    func testActionRejectedMessageSurfacesAsErrorMessage() {
        let vm = GameViewModel(playerName: "Alice")
        let hostPeer = MCPeerID(displayName: "Host#0000")

        vm.manager.onReceiveMessage?(.actionRejected(reason: "It's not your turn."), hostPeer)

        XCTAssertEqual(vm.errorMessage, "It's not your turn.")
    }

    func testJoinerReturnsToMenuWhenHostDisconnects() {
        let vm = GameViewModel(playerName: "Alice")
        vm.isHost = false
        vm.phase = .lobby
        let hostPeer = MCPeerID(displayName: "Host#0000")

        vm.manager.onPeerDisconnected?(hostPeer)

        XCTAssertEqual(vm.phase, .menu)
        XCTAssertNotNil(vm.errorMessage)
    }

    func testHostDisconnectRemovesPlayerFromLobby() {
        let vm = GameViewModel(playerName: "Alice")
        vm.isHost = true
        let bobPeer = MCPeerID(displayName: "Bob#0000")
        vm.lobby = LobbyState(players: [
            LobbyPlayer(id: vm.localPlayerId, name: "Alice", isHost: true),
            LobbyPlayer(id: bobPeer.displayName, name: "Bob", isHost: false),
        ])
        vm.phase = .lobby

        vm.manager.onPeerDisconnected?(bobPeer)

        XCTAssertEqual(vm.lobby.players.count, 1)
        XCTAssertEqual(vm.lobby.players.first?.id, vm.localPlayerId)
    }

    // MARK: - didNotStartAdvertising/Browsing surfacing (regression coverage)

    func testFailedAdvertisingSurfacesAsErrorMessage() {
        let vm = GameViewModel(playerName: "Alice")

        vm.manager.onFailedToStartAdvertising?(NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "denied"]))

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.errorMessage?.contains("denied") ?? false)
    }

    func testFailedBrowsingSurfacesAsErrorMessage() {
        let vm = GameViewModel(playerName: "Alice")

        vm.manager.onFailedToStartBrowsing?(NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "denied"]))

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.errorMessage?.contains("denied") ?? false)
    }
}
