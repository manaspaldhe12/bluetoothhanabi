import SwiftUI
import HanabiKit

struct FireworksView: View {
    let playedStacks: [CardColor: Int]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(CardColor.displayOrder) { color in
                let played = playedStacks[color] ?? 0
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(played > 0 ? color.swiftUIColor.opacity(0.55) : Color.gray.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(color.swiftUIColor, lineWidth: played == 5 ? 3 : 1)
                        )
                    Text(played > 0 ? "\(played)" : "–")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(played == 0 ? Color.gray : (color == .white ? Color.black.opacity(0.7) : Color.white))
                }
                .frame(width: 46, height: 60)
            }
        }
    }
}
