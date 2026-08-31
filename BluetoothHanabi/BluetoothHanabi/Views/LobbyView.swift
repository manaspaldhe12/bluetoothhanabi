import SwiftUI
import HanabiKit

struct LobbyView: View {
    @ObservedObject var viewModel: GameViewModel
    @State private var showingDebugLog = false

    var body: some View {
        VStack(spacing: 20) {
            Text(viewModel.isHost ? "Hosting" : "Lobby")
                .font(.title.bold())

            List(viewModel.lobby.players) { player in
                HStack {
                    Image(systemName: player.isHost ? "crown.fill" : "person.fill")
                        .foregroundStyle(player.isHost ? Color.yellow : Color.gray)
                    Text(player.name)
                    if player.id == viewModel.localPlayerId {
                        Text("(you)").foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .listStyle(.plain)
            .frame(maxHeight: 300)

            if viewModel.isHost {
                VStack(spacing: 8) {
                    Button("Start Game (\(viewModel.lobby.players.count) players)") {
                        viewModel.startGame()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!viewModel.lobby.canStart)

                    if !viewModel.lobby.canStart {
                        Text("Need at least \(LobbyState.minPlayers) players to start.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ProgressView("Waiting for the host to start…")
            }

            Spacer()
        }
        .padding()
        .navigationTitle(viewModel.isHost ? "Hosting" : "Lobby")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Leave") { viewModel.leaveGame() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Log") { showingDebugLog = true }
            }
        }
        .sheet(isPresented: $showingDebugLog) {
            DebugLogView(manager: viewModel.manager)
        }
    }
}
