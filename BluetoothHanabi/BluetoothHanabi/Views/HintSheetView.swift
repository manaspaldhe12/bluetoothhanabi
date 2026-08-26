import SwiftUI
import HanabiKit

struct HintSheetView: View {
    @ObservedObject var viewModel: GameViewModel
    let others: [PlayerState]
    var preselectedTargetId: String?

    @Environment(\.dismiss) private var dismiss
    @State private var targetId: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Who") {
                    Picker("Player", selection: $targetId) {
                        ForEach(others) { player in
                            Text(player.name).tag(Optional(player.id))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if let target = others.first(where: { $0.id == targetId }) {
                    Section("Color") {
                        colorGrid(for: target)
                    }
                    Section("Number") {
                        numberGrid(for: target)
                    }
                }
            }
            .navigationTitle("Give a Hint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                targetId = preselectedTargetId ?? others.first?.id
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func colorGrid(for target: PlayerState) -> some View {
        let presentColors = Set(target.hand.map(\.card.color))
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
            ForEach(CardColor.displayOrder) { color in
                let matches = presentColors.contains(color)
                Button {
                    give(.color(color), to: target)
                } label: {
                    Circle()
                        .fill(color.swiftUIColor)
                        .frame(width: 36, height: 36)
                        .opacity(matches ? 1 : 0.25)
                }
                .disabled(!matches)
            }
        }
        .padding(.vertical, 4)
    }

    private func numberGrid(for target: PlayerState) -> some View {
        let presentNumbers = Set(target.hand.map(\.card.number))
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
            ForEach(1...5, id: \.self) { number in
                let matches = presentNumbers.contains(number)
                Button {
                    give(.number(number), to: target)
                } label: {
                    Text("\(number)")
                        .font(.title3.bold())
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.accentColor.opacity(matches ? 0.2 : 0.05)))
                }
                .disabled(!matches)
            }
        }
        .padding(.vertical, 4)
    }

    private func give(_ type: HintType, to target: PlayerState) {
        viewModel.perform(.hint(targetPlayerId: target.id, type: type))
        dismiss()
    }
}
