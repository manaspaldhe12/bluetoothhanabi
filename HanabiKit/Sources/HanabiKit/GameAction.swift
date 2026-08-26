import Foundation

public enum HintType: Codable, Equatable, Sendable {
    case color(CardColor)
    case number(Int)
}

public enum GameAction: Codable, Equatable, Sendable {
    /// Index into the acting player's own hand.
    case play(handIndex: Int)
    /// Index into the acting player's own hand.
    case discard(handIndex: Int)
    case hint(targetPlayerId: String, type: HintType)
}

public enum EngineError: Error, Equatable, Sendable {
    case notYourTurn
    case gameAlreadyFinished
    case invalidHandIndex
    case noHintTokensAvailable
    case cannotDiscardAtMaxHintTokens
    case cannotTargetSelfWithHint
    case unknownTargetPlayer
    case hintMustMatchAtLeastOneCard
}

public struct ActionOutcome: Equatable, Sendable {
    public let description: String
    public let wasMistake: Bool

    public init(description: String, wasMistake: Bool) {
        self.description = description
        self.wasMistake = wasMistake
    }
}
