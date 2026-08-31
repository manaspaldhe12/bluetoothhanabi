import SwiftUI
import UIKit

/// Shows MultipeerManager's live networking log in-app, so diagnosing a "can't find peer"
/// issue doesn't require connecting the phone to a Mac and using Console.app.
struct DebugLogView: View {
    @ObservedObject var manager: MultipeerManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        if manager.log.isEmpty {
                            Text("No events yet.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(manager.log.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .onChange(of: manager.log.count) {
                    if let lastIndex = manager.log.indices.last {
                        withAnimation {
                            proxy.scrollTo(lastIndex, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    if let lastIndex = manager.log.indices.last {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                }
            }
            .navigationTitle("Debug Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        UIPasteboard.general.string = manager.log.joined(separator: "\n")
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }
}
