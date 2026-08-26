import SwiftUI

struct JoinGameView: View {
    @ObservedObject var viewModel: GameViewModel

    var body: some View {
        List {
            Section {
                if viewModel.availableHosts.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Searching for nearby games…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(viewModel.availableHosts, id: \.self) { peer in
                        Button {
                            viewModel.join(peer)
                        } label: {
                            HStack {
                                Image(systemName: "gamecontroller.fill")
                                Text(GameViewModel.strippedName(peer))
                                Spacer()
                                if viewModel.isConnectingToHost {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(viewModel.isConnectingToHost)
                    }
                }
            } header: {
                Text("Nearby games")
            } footer: {
                Text("Make sure the host has started hosting and Bluetooth/Wi-Fi and Local Network access are allowed.")
            }
        }
        .navigationTitle("Join Game")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { viewModel.cancelBrowsing() }
            }
        }
    }
}
