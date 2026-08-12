import SwiftUI

/// Trailing swipe-to-reveal action row for ScrollView / LazyVStack lists (History threads).
///
/// Foreground content always uses the full list width. Delete is not in the view tree at rest;
/// when swiped, it is drawn in the trailing reveal strip only.
struct SecretarySwipeActionRow<Content: View>: View {
    let rowID: String
    @Binding var openRowID: String?
    var actionWidth: CGFloat = 88
    let onDelete: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var dragOffset: CGFloat = 0

    private var isOpen: Bool {
        openRowID == rowID
    }

    private var revealOffset: CGFloat {
        let settled = isOpen ? -actionWidth : 0
        return min(0, max(-actionWidth, settled + dragOffset))
    }

    /// Delete exists in the hierarchy only while the row is materially swiped left.
    private var isActionVisible: Bool {
        revealOffset < -1
    }

    /// Trailing strip width exposed during drag; button stays `actionWidth` and is clipped.
    private var visibleRevealWidth: CGFloat {
        guard isActionVisible else { return 0 }
        return min(actionWidth, abs(revealOffset))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if isActionVisible {
                deleteAction
                    .frame(width: actionWidth)
                    .frame(maxHeight: .infinity)
                    .frame(width: visibleRevealWidth, alignment: .trailing)
                    .clipped()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.opacity)
            }

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(x: revealOffset)
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .highPriorityGesture(swipeGesture)
        .animation(.easeOut(duration: 0.18), value: isActionVisible)
        .onChange(of: openRowID) { _, newValue in
            if newValue != rowID {
                dragOffset = 0
            }
        }
    }

    private var deleteAction: some View {
        Button(action: onDelete) {
            VStack(spacing: 4) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("Remove")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(Color.white)
            .frame(width: actionWidth)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.red.opacity(0.92))
            )
        }
        .buttonStyle(.plain)
        .allowsHitTesting(isActionVisible)
        .accessibilityLabel("Remove")
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > abs(dy) else { return }

                if let open = openRowID, open != rowID {
                    openRowID = nil
                }

                if isOpen {
                    dragOffset = min(actionWidth, max(0, dx))
                } else {
                    dragOffset = min(0, max(-actionWidth, dx))
                }
            }
            .onEnded { _ in
                let offsetAtRelease = revealOffset
                let openThreshold = -actionWidth * 0.35
                let shouldStayOpen = offsetAtRelease <= openThreshold

                dragOffset = 0

                if shouldStayOpen {
                    openRowID = rowID
                } else if isOpen || openRowID == rowID {
                    withAnimation(.easeOut(duration: 0.22)) {
                        openRowID = nil
                    }
                }
            }
    }
}
