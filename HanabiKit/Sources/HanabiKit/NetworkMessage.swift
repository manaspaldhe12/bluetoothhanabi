import Foundation

/// A player as known to the lobby, before a game has started.
public struct LobbyPlayer: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var isHost: Bool

    public init(id: String, name: String, isHost: Bool) {
        self.id = id
        self.name = name
        self.isHost = isHost
    }
}

public struct LobbyState: Codable, Equatable, Sendable {
    public var players: [LobbyPlayer]

    public init(players: [LobbyPlayer]) {
        self.players = players
    }

    public static let minPlayers = 2
    public static let maxPlayers = 5
    public var canStart: Bool { players.count >= LobbyState.minPlayers && players.count <= LobbyState.maxPlayers }
}

/// Everything sent over the MultipeerConnectivity session. Clients only ever send
/// `.action` and `.joinRequest`; the host sends everything else. This keeps the protocol
/// simple: the host is the only party allowed to mutate authoritative state.
public enum NetworkMessage: Codable, Equatable, Sendable {
    case joinRequest(name: String)
    case lobbyUpdate(LobbyState)
    case gameStarted(GameState)
    case gameStateUpdate(GameState)
    case action(GameAction)
    case actionRejected(reason: String)
    case returnedToLobby(LobbyState)
}

public extension NetworkMessage {
    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) throws -> NetworkMessage {
        try JSONDecoder().decode(NetworkMessage.self, from: data)
    }
}
