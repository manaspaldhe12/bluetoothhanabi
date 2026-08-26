import SwiftUI
import HanabiKit

extension CardColor {
    var swiftUIColor: Color {
        switch self {
        case .red: return .red
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .white: return Color(white: 0.82)
        }
    }
}

/// Renders one card. Pass `card: nil` to render a masked card (used for the local player's
/// own hand) — in that case only whatever `knowledge` reveals is shown.
struct CardView: View {
    var card: Card?
    var knowledge: CardKnowledge?
    var height: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: height * 0.14)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: height * 0.14)
                        .strokeBorder(borderColor, lineWidth: knowledge?.knownColor != nil ? 3 : 1)
                )
            Text(numberText)
                .font(.system(size: height * 0.38, weight: .bold, design: .rounded))
                .foregroundStyle(numberColor)
        }
        .frame(width: height * 0.72, height: height)
        .accessibilityLabel(accessibilityLabel)
    }

    private var backgroundColor: Color {
        if let card { return card.color.swiftUIColor }
        if let known = knowledge?.knownColor { return known.swiftUIColor.opacity(0.55) }
        return Color.gray.opacity(0.25)
    }

    private var borderColor: Color {
        if let known = knowledge?.knownColor { return known.swiftUIColor }
        return Color.primary.opacity(0.25)
    }

    private var numberText: String {
        if let card { return "\(card.number)" }
        if let n = knowledge?.knownNumber { return "\(n)" }
        return "?"
    }

    private var numberColor: Color {
        if card?.color == .white { return .black.opacity(0.7) }
        return card != nil ? .white : .primary
    }

    private var accessibilityLabel: String {
        if let card { return "\(card.color.rawValue) \(card.number)" }
        var parts: [String] = []
        if let c = knowledge?.knownColor { parts.append(c.rawValue) }
        if let n = knowledge?.knownNumber { parts.append("\(n)") }
        return parts.isEmpty ? "Unknown card" : parts.joined(separator: " ")
    }
}

#Preview {
    HStack {
        CardView(card: Card(color: .red, number: 3))
        CardView(card: nil, knowledge: {
            var k = CardKnowledge()
            k.knownColor = .blue
            return k
        }())
        CardView(card: nil, knowledge: CardKnowledge())
    }
}
