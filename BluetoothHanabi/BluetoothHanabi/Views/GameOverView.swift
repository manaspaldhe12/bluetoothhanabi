import SwiftUI
import HanabiKit

struct GameOverView: View {
    @ObservedObject var viewModel: GameViewModel
    let state: GameState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(headline).font(.system(size: 48))
            Text(title).font(.largeTitle.bold())
            Text("\(state.score) / 25")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.accentColor)
            Text(reasonText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            FireworksView(playedStacks: state.playedStacks)

            if viewModel.isHost {
                Button("Back to Lobby") { viewModel.returnToLobby() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else {
                Text("Waiting for the host…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button("Leave", role: .destructive) { viewModel.leaveGame() }
                .buttonStyle(.bordered)

            Spacer()
        }
        .padding()
        .navigationBarBackButtonHidden(true)
    }

    private var headline: String {
        switch state.finishReason {
        case .perfectScore: return "🎉"
        case .outOfLives: return "💥"
        default: return "🎆"
        }
    }

    private var title: String {
        switch state.finishReason {
        case .perfectScore: return "Perfect Score!"
        case .outOfLives: return "Out of Lives"
        default: return "Game Over"
        }
    }

    private var reasonText: String {
        switch state.finishReason {
        case .perfectScore: return "The whole team lit up every firework. Flawless."
        case .outOfLives: return "Three mistakes ended the show early."
        case .deckExhausted: return "The deck ran out and everyone got their last turn."
        case .none: return ""
        }
    }
}
