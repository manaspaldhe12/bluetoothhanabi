import Foundation
import MultipeerConnectivity
import HanabiKit

enum AppPhase: Equatable {
    case menu
    case browsingForHost
    case lobby
    case game
}

@MainActor
final class GameViewModel: ObservableObject {
    @Published private(set) var phase: AppPhase = .menu
    @Published private(set) var lobby = LobbyState(players: [])
    @Published private(set) var gameState: GameState?
    @Published var errorMessage: String?
    @Published private(set) var isConnectingToHost = false

    let manager: MultipeerManager
    private(set) var isHost = false
    private var hostGame: HostGame?

    var localPlayerId: String { manager.myPeerId.displayName }

    /// The chosen name without the disambiguating "#XXXX" suffix baked into the peer ID.
    let displayPlayerName: String

    init(playerName: String) {
        let trimmed = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        displayPlayerName = trimmed.isEmpty ? "Player" : trimmed
        let suffix = String(UUID().uuidString.prefix(4))
        manager = MultipeerManager(displayName: "\(displayPlayerName)#\(suffix)")

        manager.onReceiveMessage = { [weak self] message, peer in
            self?.handle(message, from: peer)
        }
        manager.onPeerConnected = { [weak self] peer in
            self?.handlePeerConnected(peer)
        }
        manager.onPeerDisconnected = { [weak self] peer in
            self?.handlePeerDisconnected(peer)
        }
        manager.shouldAcceptInvitation = { [weak self] in
            guard let self else { return false }
            return self.lobby.players.count < LobbyState.maxPlayers
        }
        manager.onFailedToStartAdvertising = { [weak self] error in
            self?.errorMessage = "Couldn't start hosting (\(error.localizedDescription)). Check Settings → Privacy & Security → Local Network and make sure Hanabi is allowed."
        }
        manager.onFailedToStartBrowsing = { [weak self] error in
            self?.errorMessage = "Couldn't search for games (\(error.localizedDescription)). Check Settings → Privacy & Security → Local Network and make sure Hanabi is allowed."
        }
    }

    static func strippedName(_ peer: MCPeerID) -> String {
        String(peer.displayName.split(separator: "#").first ?? Substring(peer.displayName))
    }

    var availableHosts: [MCPeerID] { manager.availableHosts }

    // MARK: - Host flow

    func startHosting() {
        isHost = true
        lobby = LobbyState(players: [LobbyPlayer(id: localPlayerId, name: displayPlayerName, isHost: true)])
        phase = .lobby
        manager.startHosting()
    }

    func startGame() {
        guard isHost, lobby.canStart else { return }
        let players = lobby.players.map { (id: $0.id, name: $0.name) }
        let game = HostGame(players: players)
        hostGame = game
        gameState = game.state
        phase = .game
        manager.stopHosting()
        manager.send(.gameStarted(game.state))
    }

    func returnToLobby() {
        guard isHost else { return }
        hostGame = nil
        gameState = nil
        phase = .lobby
        manager.startHosting()
        manager.send(.returnedToLobby(lobby))
    }

    // MARK: - Client flow

    func startBrowsingForHosts() {
        isHost = false
        phase = .browsingForHost
        manager.startBrowsing()
    }

    func cancelBrowsing() {
        manager.stopBrowsing()
        phase = .menu
    }

    func join(_ peer: MCPeerID) {
        isConnectingToHost = true
        manager.invite(peer)
    }

    // MARK: - Leaving

    func leaveGame() {
        manager.disconnect()
        hostGame = nil
        gameState = nil
        lobby = LobbyState(players: [])
        isHost = false
        isConnectingToHost = false
        phase = .menu
    }

    // MARK: - Gameplay actions (both host and clients call this same entry point)

    func perform(_ action: GameAction) {
        if isHost {
            applyHostAction(action, by: localPlayerId)
        } else {
            manager.send(.action(action))
        }
    }

    private func applyHostAction(_ action: GameAction, by playerId: String) {
        guard let hostGame else { return }
        do {
            try hostGame.apply(action, by: playerId)
            gameState = hostGame.state
            manager.send(.gameStateUpdate(hostGame.state))
        } catch {
            let reason = Self.describe(error)
            if playerId == localPlayerId {
                errorMessage = reason
            } else if let peer = manager.session.connectedPeers.first(where: { $0.displayName == playerId }) {
                manager.send(.actionRejected(reason: reason), to: [peer])
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        guard let engineError = error as? EngineError else { return "Something went wrong." }
        switch engineError {
        case .notYourTurn: return "It's not your turn."
        case .gameAlreadyFinished: return "The game has already finished."
        case .invalidHandIndex: return "That card no longer exists."
        case .noHintTokensAvailable: return "No hint tokens left."
        case .cannotDiscardAtMaxHintTokens: return "Hint tokens are already full — discarding is disabled."
        case .cannotTargetSelfWithHint: return "You can't hint yourself."
        case .unknownTargetPlayer: return "That player isn't in the game."
        case .hintMustMatchAtLeastOneCard: return "That hint doesn't match any of their cards."
        }
    }

    // MARK: - Networking callbacks

    private func handlePeerConnected(_ peer: MCPeerID) {
        guard !isHost else { return }
        isConnectingToHost = false
        manager.send(.joinRequest(name: displayPlayerName))
    }

    private func handlePeerDisconnected(_ peer: MCPeerID) {
        if isHost {
            lobby.players.removeAll { $0.id == peer.displayName }
            if phase == .lobby {
                manager.send(.lobbyUpdate(lobby))
            }
        } else if phase != .menu {
            errorMessage = "Disconnected from the host."
            leaveGame()
        }
    }

    private func handle(_ message: NetworkMessage, from peer: MCPeerID) {
        switch message {
        case .joinRequest(let name):
            guard isHost else { return }
            guard lobby.players.count < LobbyState.maxPlayers else {
                manager.send(.actionRejected(reason: "Lobby is full."), to: [peer])
                return
            }
            if !lobby.players.contains(where: { $0.id == peer.displayName }) {
                lobby.players.append(LobbyPlayer(id: peer.displayName, name: name, isHost: false))
            }
            manager.send(.lobbyUpdate(lobby))

        case .lobbyUpdate(let newLobby):
            guard !isHost else { return }
            lobby = newLobby
            phase = .lobby

        case .gameStarted(let state), .gameStateUpdate(let state):
            guard !isHost else { return }
            gameState = state
            phase = .game

        case .action(let action):
            guard isHost else { return }
            applyHostAction(action, by: peer.displayName)

        case .actionRejected(let reason):
            errorMessage = reason

        case .returnedToLobby(let newLobby):
            guard !isHost else { return }
            lobby = newLobby
            gameState = nil
            phase = .lobby
        }
    }
}
