import SwiftUI

struct TokenTrackView: View {
    let label: String
    let systemImage: String
    let filled: Int
    let total: Int
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(0..<total, id: \.self) { index in
                    Image(systemName: systemImage)
                        .foregroundStyle(index < filled ? tint : Color.gray.opacity(0.3))
                }
            }
        }
    }
}
