import SwiftUI

struct MainMenuView: View {
    @ObservedObject var viewModel: GameViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("🎆").font(.system(size: 56))
            Text("Hanabi").font(.largeTitle.bold())
            Text("Playing as \(viewModel.displayPlayerName)")
                .foregroundStyle(.secondary)

            VStack(spacing: 16) {
                Button {
                    viewModel.startHosting()
                } label: {
                    Label("Host Game", systemImage: "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    viewModel.startBrowsingForHosts()
                } label: {
                    Label("Join Game", systemImage: "person.2.wave.2")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .padding(.horizontal, 40)

            Text("2–5 players, same room, Bluetooth or Wi-Fi.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .navigationBarBackButtonHidden(true)
    }
}
