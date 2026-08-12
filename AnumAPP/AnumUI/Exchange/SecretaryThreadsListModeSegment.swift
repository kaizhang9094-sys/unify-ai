import SwiftUI

/// Slim Recent / History segmented control for the Threads tab.
struct SecretaryThreadsListModeSegment: View {
    @Binding var selection: SecretaryThreadListView.ListMode

    private let controlHeight: CGFloat = 38

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SecretaryThreadListView.ListMode.allCases) { mode in
                segmentButton(mode)
            }
        }
        .padding(3)
        .frame(maxWidth: .infinity)
        .frame(height: controlHeight)
        .background {
            RoundedRectangle(cornerRadius: controlHeight / 2, style: .continuous)
                .fill(SecretaryTheme.white.opacity(0.06))
        }
        .overlay(
            RoundedRectangle(cornerRadius: controlHeight / 2, style: .continuous)
                .stroke(SecretaryTheme.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func segmentButton(_ mode: SecretaryThreadListView.ListMode) -> some View {
        let isSelected = selection == mode

        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selection = mode
            }
        } label: {
            Text(mode.rawValue)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    isSelected ? SecretaryTheme.darkPrimaryText : SecretaryTheme.darkSecondaryText
                )
                .frame(maxWidth: .infinity)
                .frame(height: controlHeight - 6)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: (controlHeight - 6) / 2, style: .continuous)
                            .fill(SecretaryTheme.darkOrange.opacity(0.22))
                            .overlay(
                                RoundedRectangle(cornerRadius: (controlHeight - 6) / 2, style: .continuous)
                                    .stroke(SecretaryTheme.darkOrange.opacity(0.45), lineWidth: 1)
                            )
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
