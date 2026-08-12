import SwiftUI

/// Trailing swipe-to-reveal actions for ScrollView / LazyVStack lists (Chat conversations, etc.).
///
/// Foreground content keeps full list width. Actions are not in the tree at rest; each action stays
/// a fixed width and is revealed by clipping from the trailing edge.
struct SecretarySwipeRowAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    init(
        id: String,
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }
}

struct SecretarySwipeActionsRow<Content: View>: View {
    let rowID: String
    @Binding var openRowID: String?
    var actionWidth: CGFloat = 88
    let actions: [SecretarySwipeRowAction]
    @ViewBuilder var content: () -> Content

    @State private var dragOffset: CGFloat = 0

    private var isOpen: Bool {
        openRowID == rowID
    }

    private var totalActionWidth: CGFloat {
        actionWidth * CGFloat(max(actions.count, 1))
    }

    private var revealOffset: CGFloat {
        let settled = isOpen ? -totalActionWidth : 0
        return min(0, max(-totalActionWidth, settled + dragOffset))
    }

    private var isActionVisible: Bool {
        revealOffset < -1 && !actions.isEmpty
    }

    private var visibleRevealWidth: CGFloat {
        guard isActionVisible else { return 0 }
        return min(totalActionWidth, abs(revealOffset))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if isActionVisible {
                trailingActions
                    .frame(width: totalActionWidth)
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

    private var trailingActions: some View {
        HStack(spacing: 0) {
            ForEach(actions) { action in
                actionButton(action)
            }
        }
    }

    private func actionButton(_ action: SecretarySwipeRowAction) -> some View {
        Button(action: action.action) {
            VStack(spacing: 4) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                Text(action.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(Color.white)
            .frame(width: actionWidth)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(action.tint)
            )
        }
        .buttonStyle(.plain)
        .allowsHitTesting(isActionVisible)
        .accessibilityLabel(action.title)
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
                    dragOffset = min(totalActionWidth, max(0, dx))
                } else {
                    dragOffset = min(0, max(-totalActionWidth, dx))
                }
            }
            .onEnded { _ in
                let offsetAtRelease = revealOffset
                let openThreshold = -totalActionWidth * 0.35
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
