import SwiftUI
import HanabiKit

struct HandView: View {
    let hand: [HandCard]
    let isOwnHand: Bool
    var highlightIndex: Int? = nil
    var onTapCard: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(hand.enumerated()), id: \.element.id) { index, handCard in
                Button {
                    onTapCard?(index)
                } label: {
                    VStack(spacing: 4) {
                        CardView(card: isOwnHand ? nil : handCard.card, knowledge: handCard.knowledge)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .stroke(Color.accentColor, lineWidth: highlightIndex == index ? 3 : 0)
                            )
                        if isOwnHand {
                            Text(captionText(handCard.knowledge))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(minHeight: 14)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(onTapCard == nil)
            }
        }
    }

    private func captionText(_ k: CardKnowledge) -> String {
        var parts: [String] = []
        if let c = k.knownColor { parts.append(c.rawValue.capitalized) }
        if let n = k.knownNumber { parts.append("\(n)") }
        return parts.isEmpty ? " " : parts.joined(separator: " ")
    }
}
