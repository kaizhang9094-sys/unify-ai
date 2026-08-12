import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins
import AnumCore

/// Manual “Add contact” entry: share invite + send a contact request.
struct SecretaryAddTrustedContactSheet: View {
    @EnvironmentObject private var services: AppServices
    @Environment(\.dismiss) private var dismiss

    enum CompletionAction: Equatable {
        case sentRequest
        case addedLocal
    }

    let onFinished: (_ nodeID: String?, _ displayName: String?, _ action: CompletionAction) -> Void

    @State private var nodeOrLinkInput: String = ""
    @State private var displayNameInput: String = ""
    @State private var noteInput: String = ""
    @State private var ownNodeID: String?
    @State private var ownDisplayName: String?
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var successText: String?
    @State private var didCopyNodeID = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    shareInviteCard

                    addSomeoneSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
            .background(UnifyIceShellBackground())
            .navigationTitle("Add contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .disabled(isWorking)
                }
            }
            .task {
                ownNodeID = await services.exchangeNodeID?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                ownDisplayName = await services.localExchangeDisplayName()?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        .tint(SecretaryTheme.darkOrange)
        .preferredColorScheme(.dark)
    }

    // MARK: - Share invite

    @ViewBuilder
    private var shareInviteCard: some View {
        if let nodeID = ownNodeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
            let sharePayload = AddFriendInviteBuilder.inviteShareText(
                nodeID: nodeID,
                displayName: ownDisplayName
            )
            let nodeIDCopyPayload = AddFriendInviteBuilder.nodeIDForCopy(nodeID)

            UnifyDarkCard(cornerRadius: 24, strokeOpacity: 0.92) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(SecretaryTheme.darkOrangeSoft.opacity(0.42))
                                .frame(width: 40, height: 40)
                            Image(systemName: "link.badge.plus")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(SecretaryTheme.darkOrange)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Invite someone to Unify")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(SecretaryTheme.darkPrimaryText)

                            Text("Share invite for new users, or copy your node ID if they already have Unify.")
                                .font(.system(size: 13.5))
                                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Text(nodeIDCopyPayload)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            UnifyGlassTextFieldChrome(cornerRadius: 14, strokeOpacity: 0.65)
                        }

                    HStack(spacing: 10) {
                        ShareLink(item: sharePayload) {
                            inviteActionLabel(
                                title: "Share invite",
                                systemImage: "square.and.arrow.up",
                                isPrimary: true
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            UIPasteboard.general.string = nodeIDCopyPayload
                            didCopyNodeID = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                didCopyNodeID = false
                            }
                        } label: {
                            inviteActionLabel(
                                title: didCopyNodeID ? "Copied" : "Copy Node ID",
                                systemImage: didCopyNodeID ? "checkmark" : "doc.on.doc",
                                isPrimary: false
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
    }

    private func inviteActionLabel(title: String, systemImage: String, isPrimary: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 13.5, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(isPrimary ? Color.white : SecretaryTheme.darkPrimaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background {
                if isPrimary {
                    Capsule(style: .continuous)
                        .fill(SecretaryTheme.darkOrange)
                } else {
                    UnifyGlassCapsuleChrome()
                }
            }
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        SecretaryTheme.darkStroke.opacity(isPrimary ? 0.35 : 0.55),
                        lineWidth: 1
                    )
            )
    }

    // MARK: - Add someone

    private var addSomeoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add someone")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkMutedText)
                .textCase(.uppercase)
                .tracking(0.6)

            UnifyDarkCard(cornerRadius: 24, strokeOpacity: 0.92) {
                VStack(alignment: .leading, spacing: 16) {
                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkOrange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let successText {
                        Text(successText)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(SecretaryTheme.darkPrimaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    labeledField(
                        title: "Paste node ID or invite text",
                        placeholder: "Paste node ID or invite text",
                        helper: "Use their node ID, invite text, or a legacy invite link.",
                        text: $nodeOrLinkInput
                    )

                    labeledField(
                        title: "Nickname (optional)",
                        placeholder: "How you want to remember them",
                        helper: "Nickname only you can see.",
                        text: $displayNameInput
                    )

                    labeledField(
                        title: "Message (optional)",
                        placeholder: "Add a short message",
                        helper: "They’ll see this with your request.",
                        text: $noteInput,
                        axis: .vertical,
                        lines: 2...5
                    )

                    sendRequestButton
                }
                .padding(16)
            }
        }
    }

    // MARK: - Fields

    private func labeledField(
        title: String,
        placeholder: String,
        helper: String? = nil,
        text: Binding<String>,
        axis: Axis = .horizontal,
        lines: ClosedRange<Int>? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)

            if let lines {
                TextField(placeholder, text: text, axis: axis)
                    .font(.system(size: 16))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .tint(SecretaryTheme.darkOrange)
                    .lineLimit(lines)
                    .padding(14)
                    .background {
                        UnifyGlassTextFieldChrome(cornerRadius: 16, strokeOpacity: 0.72)
                    }
                    .disabled(isWorking)
            } else {
                TextField(placeholder, text: text)
                    .font(.system(size: 16))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText)
                    .tint(SecretaryTheme.darkOrange)
                    .padding(14)
                    .background {
                        UnifyGlassTextFieldChrome(cornerRadius: 16, strokeOpacity: 0.72)
                    }
                    .disabled(isWorking)
            }

            if let helper, !helper.isEmpty {
                Text(helper)
                    .font(.system(size: 12.5))
                    .foregroundStyle(SecretaryTheme.darkMutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var canSubmit: Bool {
        !isWorking && !nodeOrLinkInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sendRequestButton: some View {
        Button {
            Task { await sendRequest() }
        } label: {
            Text(isWorking ? "Sending…" : "Send request")
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(canSubmit ? Color.white : SecretaryTheme.darkPrimaryText.opacity(0.55))
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            canSubmit
                                ? SecretaryTheme.darkOrange
                                : SecretaryTheme.darkOrangeSoft.opacity(0.28)
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            SecretaryTheme.darkOrange.opacity(canSubmit ? 0.45 : 0.22),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .padding(.top, 4)
    }

    // MARK: - Submit

    @MainActor
    private func sendRequest() async {
        errorText = nil
        successText = nil
        isWorking = true
        defer { isWorking = false }

        guard let sourceNodeID = await services.exchangeNodeID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !sourceNodeID.isEmpty
        else {
            errorText = "Your local Exchange node is not ready yet."
            return
        }

        let displayTrim = displayNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteTrim = noteInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let parse = ManualTrustedContactInputNormalizer.parse(nodeOrLinkInput)
        #if DEBUG
        print("[AddContactInput] parsedNodeID=\(parse.nodeID ?? "nil") source=\(parse.source.rawValue)")
        #endif

        do {
            #if DEBUG
            print("[AddContactMode] mode=sendRequest nodeID=\(parse.nodeID ?? "nil")")
            #endif
            let result = try await services.exchangeFacade.sendContactRequestToNode(
                sourceNodeID: sourceNodeID,
                targetNodeID: nodeOrLinkInput,
                displayNameOverride: displayTrim.isEmpty ? nil : displayTrim,
                note: noteTrim.isEmpty ? nil : noteTrim
            )
            successText = "Request sent."
            #if DEBUG
            print("[AddContactSuccess] nodeID=\(result.targetNodeID) displayName=\(displayTrim.isEmpty ? "nil" : displayTrim) hydrated=\(result.hydratedFromDirectory)")
            #endif
            dismiss()

            NotificationCenter.default.post(
                name: .secretaryWorkspaceShouldRefresh,
                object: nil,
                userInfo: nil
            )

            onFinished(
                result.targetNodeID,
                displayTrim.isEmpty ? nil : displayTrim,
                .sentRequest
            )
        } catch {
            #if DEBUG
            print("[ContactRequestSend] targetNodeID=\(nodeOrLinkInput.trimmingCharacters(in: .whitespacesAndNewlines)) hydrated=false queued=false threadID=nil envelopeID=nil")
            #endif
            errorText = mapAddContactError(error)
        }
    }

    #if DEBUG
    /// Dev-only local trust path; not exposed in the Add Contact UI.
    @MainActor
    private func addLocal() async {
        errorText = nil
        successText = nil
        isWorking = true
        defer { isWorking = false }

        guard let sourceNodeID = await services.exchangeNodeID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !sourceNodeID.isEmpty
        else {
            errorText = "Your local Exchange node is not ready yet."
            return
        }
        let displayTrim = displayNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteTrim = noteInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let parse = ManualTrustedContactInputNormalizer.parse(nodeOrLinkInput)
        print("[AddContactMode] mode=addLocal nodeID=\(parse.nodeID ?? "nil")")
        do {
            let edge = try await services.exchangeFacade.addManualTrustedContact(
                sourceNodeID: sourceNodeID,
                rawTargetInput: nodeOrLinkInput,
                displayNameOverride: displayTrim.isEmpty ? nil : displayTrim,
                note: noteTrim.isEmpty ? nil : noteTrim
            )
            successText = "Contact added."
            dismiss()
            NotificationCenter.default.post(
                name: .secretaryWorkspaceShouldRefresh,
                object: nil,
                userInfo: nil
            )
            onFinished(edge.targetNodeID, displayTrim.isEmpty ? nil : displayTrim, .addedLocal)
        } catch {
            errorText = mapAddContactError(error)
        }
    }
    #endif

    private func mapAddContactError(_ error: Error) -> String {
        if let store = error as? ExchangeStoreError {
            switch store {
            case .storageFailure(let reason):
                return reason
            default:
                break
            }
        }

        return "Couldn’t add this contact."
    }
}

private struct AddContactInviteQRCodeView: View {
    let payload: String

    var body: some View {
        Group {
            if let image = Self.makeImage(from: payload) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 168, height: 168)
                    .padding(14)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(SecretaryTheme.darkStroke.opacity(0.25), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(SecretaryTheme.darkSurfaceStrong.opacity(0.35))
                    .frame(width: 196, height: 196)
                    .overlay {
                        Text("QR unavailable")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(SecretaryTheme.darkMutedText)
                    }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private static func makeImage(from string: String) -> UIImage? {
        let data = Data(string.utf8)
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
