import SwiftUI
import HanabiKit

struct GameTableView: View {
    @ObservedObject var viewModel: GameViewModel
    let state: GameState

    @State private var selectedHandIndex: Int?
    @State private var showingHintSheet = false
    @State private var showingLeaveConfirmation = false
    @State private var hintTargetId: String?

    private var isMyTurn: Bool { state.currentPlayer.id == viewModel.localPlayerId }
    private var others: [PlayerState] { state.players.filter { $0.id != viewModel.localPlayerId } }
    private var me: PlayerState? { state.player(withId: viewModel.localPlayerId) }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                turnBanner

                VStack(spacing: 16) {
                    ForEach(others) { player in
                        otherHandSection(player)
                    }
                }

                VStack(spacing: 12) {
                    Text("Fireworks").font(.caption).foregroundStyle(.secondary)
                    FireworksView(playedStacks: state.playedStacks)
                }

                HStack(spacing: 32) {
                    TokenTrackView(label: "Hints", systemImage: "lightbulb.fill", filled: state.hintTokens, total: GameState.maxHintTokens, tint: .yellow)
                    TokenTrackView(label: "Lives", systemImage: "heart.fill", filled: state.lives, total: GameState.maxLives, tint: .red)
                }

                logSection
            }
            .padding()
            .padding(.bottom, 140)
        }
        .safeAreaInset(edge: .bottom) {
            if let me {
                ownHandBar(me)
            }
        }
        .navigationTitle("Hanabi")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Leave") { showingLeaveConfirmation = true }
            }
        }
        .confirmationDialog("Leave the game?", isPresented: $showingLeaveConfirmation, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { viewModel.leaveGame() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            selectedHandIndex.map { "Card \($0 + 1)" } ?? "",
            isPresented: cardActionBinding,
            titleVisibility: .visible
        ) {
            Button("Play") {
                if let index = selectedHandIndex { viewModel.perform(.play(handIndex: index)) }
                selectedHandIndex = nil
            }
            Button("Discard", role: .destructive) {
                if let index = selectedHandIndex { viewModel.perform(.discard(handIndex: index)) }
                selectedHandIndex = nil
            }
            .disabled(state.hintTokens >= GameState.maxHintTokens)
            Button("Cancel", role: .cancel) { selectedHandIndex = nil }
        } message: {
            if state.hintTokens >= GameState.maxHintTokens {
                Text("Hint tokens are full, so discarding is disabled.")
            }
        }
        .sheet(isPresented: $showingHintSheet) {
            HintSheetView(viewModel: viewModel, others: others, preselectedTargetId: hintTargetId)
        }
    }

    private var turnBanner: some View {
        VStack(spacing: 8) {
            if isMyTurn {
                Text("Your turn").font(.title2.bold()).foregroundStyle(Color.accentColor)
            } else {
                Text("\(state.currentPlayer.name)'s turn").font(.title2.bold())
            }
            Text("\(state.drawPileCount) cards left in the deck")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let remaining = state.finalRoundTurnsRemaining {
                Text("Final round: \(remaining) turn\(remaining == 1 ? "" : "s") left")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
        }
    }

    private func otherHandSection(_ player: PlayerState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(player.name).font(.subheadline.bold())
                if player.id == state.currentPlayer.id {
                    Image(systemName: "arrow.right.circle.fill").foregroundStyle(Color.accentColor)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HandView(hand: player.hand, isOwnHand: false, onTapCard: isMyTurn ? { _ in presentHint(for: player) } : nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func presentHint(for player: PlayerState) {
        hintTargetId = player.id
        showingHintSheet = true
    }

    private func ownHandBar(_ me: PlayerState) -> some View {
        VStack(spacing: 8) {
            Divider()
            HStack {
                Text("Your hand").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    hintTargetId = nil
                    showingHintSheet = true
                } label: {
                    Label("Give Hint", systemImage: "lightbulb")
                }
                .buttonStyle(.bordered)
                .disabled(!isMyTurn || state.hintTokens == 0 || others.isEmpty)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HandView(hand: me.hand, isOwnHand: true, onTapCard: isMyTurn ? { index in selectedHandIndex = index } : nil)
                    .padding(.horizontal, 2)
            }
            if !isMyTurn {
                Text("Waiting for \(state.currentPlayer.name)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(.bar)
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Log").font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(state.log.suffix(6)) { entry in
                    Text(entry.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cardActionBinding: Binding<Bool> {
        Binding(
            get: { selectedHandIndex != nil },
            set: { if !$0 { selectedHandIndex = nil } }
        )
    }
}
