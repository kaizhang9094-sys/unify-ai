import SwiftUI

/// Legacy debug placeholder. The real chat UI lives in `ChatView.swift`.
///
/// Phase 7: Keep this around as a fallback while the migration stabilizes,
/// but never boot it by default.
struct LegacyContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("LegacyContentView")
                .font(.headline)
            Text("Chat UI moved to ChatView.swift")
                .foregroundStyle(.secondary)
            Text("(Not used in normal app flow)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

@available(*, deprecated, message: "Use RootView → RoomView/ChatView. This is kept only as a migration fallback.")
struct ContentView: View {
    var body: some View {
        LegacyContentView()
    }
}

#Preview("Legacy") {
    LegacyContentView()
}
