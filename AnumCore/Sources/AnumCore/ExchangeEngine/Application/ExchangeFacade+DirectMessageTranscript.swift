import Foundation

extension ExchangeFacade {
    private static let inboundReconcileTriggerLock = NSLock()
    nonisolated(unsafe) private static var activeInboundReconcileTriggerStorage: ExchangeSyncEngine.Trigger?

    func setActiveInboundReconcileTrigger(_ trigger: ExchangeSyncEngine.Trigger) {
        Self.inboundReconcileTriggerLock.lock()
        Self.activeInboundReconcileTriggerStorage = trigger
        Self.inboundReconcileTriggerLock.unlock()
    }

    func activeInboundReconcileTrigger() -> ExchangeSyncEngine.Trigger? {
        Self.inboundReconcileTriggerLock.lock()
        defer { Self.inboundReconcileTriggerLock.unlock() }
        return Self.activeInboundReconcileTriggerStorage
    }

    func postDirectMessageTranscriptDidChangeIfNeeded(for turn: ExchangeTurn) async {
        guard let thread = try? await store.fetchThread(id: turn.threadID),
              thread.metadata["direct_message_thread"]?.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        else {
            return
        }

        let counterpartyNodeID =
            thread.selectedCounterpartyID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            ?? turn.metadata["source_sender_node_id"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        guard let counterpartyNodeID, !counterpartyNodeID.isEmpty else { return }

        let direction: String
        let source: DirectMessageTranscriptChangeSource
        switch turn.actor {
        case .user, .secretary:
            direction = "outbound"
            source = .localSend
        case .counterparty:
            direction = "inbound"
            if let trigger = activeInboundReconcileTrigger() {
                source = DirectMessageTranscriptChangeSource(syncTrigger: trigger)
            } else {
                source = .inboundReconcile
            }
        default:
            return
        }

        let event = DirectMessageTranscriptChangeEvent(
            threadID: thread.id,
            counterpartyNodeID: counterpartyNodeID,
            messageID: turn.id.uuidString,
            direction: direction,
            source: source
        )

        DirectMessageTranscriptChangeNotification.logStoreWrite(event)
        await DirectMessageTranscriptChangeNotification.post(event)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
