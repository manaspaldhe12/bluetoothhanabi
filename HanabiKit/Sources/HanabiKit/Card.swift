import Foundation

public enum CardColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case red, yellow, green, blue, white

    public var id: String { rawValue }

    /// Turn order used when listing colors in the UI (fireworks display, hint pickers, etc).
    public static let displayOrder: [CardColor] = [.red, .yellow, .green, .blue, .white]
}

public struct Card: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let color: CardColor
    public let number: Int

    public init(id: UUID = UUID(), color: CardColor, number: Int) {
        self.id = id
        self.color = color
        self.number = number
    }
}

/// What a player has learned about one of their own cards from hints given to them.
/// Positive facts come from direct hints; exclusions come from hints that touched other
/// cards in the same hand but not this one (standard Hanabi "negative information").
public struct CardKnowledge: Codable, Equatable, Sendable {
    public var knownColor: CardColor?
    public var knownNumber: Int?
    public var excludedColors: Set<CardColor> = []
    public var excludedNumbers: Set<Int> = []

    public init() {}

    public var possibleColors: Set<CardColor> {
        if let knownColor { return [knownColor] }
        return Set(CardColor.allCases).subtracting(excludedColors)
    }

    public var possibleNumbers: Set<Int> {
        if let knownNumber { return [knownNumber] }
        return Set(1...5).subtracting(excludedNumbers)
    }

    mutating func apply(colorHint color: CardColor, matched: Bool) {
        if matched {
            knownColor = color
        } else {
            excludedColors.insert(color)
        }
    }

    mutating func apply(numberHint number: Int, matched: Bool) {
        if matched {
            knownNumber = number
        } else {
            excludedNumbers.insert(number)
        }
    }
}

public struct HandCard: Codable, Equatable, Identifiable, Sendable {
    public let card: Card
    public var knowledge: CardKnowledge

    public var id: UUID { card.id }

    public init(card: Card, knowledge: CardKnowledge = CardKnowledge()) {
        self.card = card
        self.knowledge = knowledge
    }
}

extension Card {
    /// Standard Hanabi deck: 5 colors, each with three 1s, two 2s, two 3s, two 4s, one 5 (50 cards total).
    public static func standardDeck() -> [Card] {
        let countsByNumber: [Int: Int] = [1: 3, 2: 2, 3: 2, 4: 2, 5: 1]
        var deck: [Card] = []
        for color in CardColor.displayOrder {
            for (number, count) in countsByNumber {
                for _ in 0..<count {
                    deck.append(Card(color: color, number: number))
                }
            }
        }
        return deck
    }
}
