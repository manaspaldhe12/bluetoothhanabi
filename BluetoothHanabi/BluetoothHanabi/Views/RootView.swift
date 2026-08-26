import SwiftUI
import UIKit

struct RootView: View {
    @State private var playerName: String = UIDevice.current.name
    @State private var viewModel: GameViewModel?

    var body: some View {
        if let viewModel {
            GameRootView(viewModel: viewModel)
        } else {
            NameEntryView(name: $playerName) {
                viewModel = GameViewModel(playerName: playerName)
            }
        }
    }
}

struct GameRootView: View {
    @ObservedObject var viewModel: GameViewModel

    var body: some View {
        NavigationStack {
            content
        }
        .alert("Heads up", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .menu:
            MainMenuView(viewModel: viewModel)
        case .browsingForHost:
            JoinGameView(viewModel: viewModel)
        case .lobby:
            LobbyView(viewModel: viewModel)
        case .game:
            if let state = viewModel.gameState {
                if state.phase == .finished {
                    GameOverView(viewModel: viewModel, state: state)
                } else {
                    GameTableView(viewModel: viewModel, state: state)
                }
            } else {
                ProgressView("Starting game…")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }
}
