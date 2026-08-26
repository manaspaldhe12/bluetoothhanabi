import Foundation

public struct PlayerState: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var hand: [HandCard]

    public init(id: String, name: String, hand: [HandCard] = []) {
        self.id = id
        self.name = name
        self.hand = hand
    }
}

public enum GamePhase: Codable, Equatable, Sendable {
    case playing
    case finished
}

public enum FinishReason: Codable, Equatable, Sendable {
    case perfectScore
    case outOfLives
    case deckExhausted
}

public struct LogEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let text: String

    public init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

/// The full, authoritative state of a game. The host owns the canonical copy (plus the
/// private draw pile, which is never sent over the network) and broadcasts this struct to
/// every peer after each action. Clients render it directly; there is no per-client
/// filtering of card identities, since the app is designed for players who trust each
/// other not to peek at their own network traffic — the UI layer is responsible for
/// hiding a player's own hand from themselves.
public struct GameState: Codable, Equatable, Sendable {
    public var players: [PlayerState]
    public var currentPlayerIndex: Int
    public var drawPileCount: Int
    public var discardPile: [Card]
    public var playedStacks: [CardColor: Int]
    public var hintTokens: Int
    public var lives: Int
    public var finalRoundTurnsRemaining: Int?
    public var phase: GamePhase
    public var finishReason: FinishReason?
    public var log: [LogEntry]

    public static let maxHintTokens = 8
    public static let maxLives = 3
    public static let maxLogEntries = 50

    public init(
        players: [PlayerState],
        currentPlayerIndex: Int,
        drawPileCount: Int,
        discardPile: [Card] = [],
        playedStacks: [CardColor: Int] = [:],
        hintTokens: Int = GameState.maxHintTokens,
        lives: Int = GameState.maxLives,
        finalRoundTurnsRemaining: Int? = nil,
        phase: GamePhase = .playing,
        finishReason: FinishReason? = nil,
        log: [LogEntry] = []
    ) {
        self.players = players
        self.currentPlayerIndex = currentPlayerIndex
        self.drawPileCount = drawPileCount
        self.discardPile = discardPile
        self.playedStacks = playedStacks
        self.hintTokens = hintTokens
        self.lives = lives
        self.finalRoundTurnsRemaining = finalRoundTurnsRemaining
        self.phase = phase
        self.finishReason = finishReason
        self.log = log
    }

    public var currentPlayer: PlayerState { players[currentPlayerIndex] }

    public var score: Int {
        if finishReason == .outOfLives { return 0 }
        return playedStacks.values.reduce(0, +)
    }

    public func player(withId id: String) -> PlayerState? {
        players.first { $0.id == id }
    }

    public func playerIndex(withId id: String) -> Int? {
        players.firstIndex { $0.id == id }
    }

    mutating func appendLog(_ text: String) {
        log.append(LogEntry(text: text))
        if log.count > GameState.maxLogEntries {
            log.removeFirst(log.count - GameState.maxLogEntries)
        }
    }
}

public extension GameState {
    static func handSize(forPlayerCount count: Int) -> Int {
        count <= 3 ? 5 : 4
    }
}
