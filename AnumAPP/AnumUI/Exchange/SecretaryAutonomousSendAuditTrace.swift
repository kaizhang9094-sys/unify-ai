import Foundation
import AnumCore

/// User-facing lines for `ExchangeAuditRecord` rows produced by autonomous-send observability.
enum SecretaryAutonomousSendAuditTrace {
    private static let traceKindKey = "trace_kind"
    private static let traceKindValue = "autonomous_send_attempt_v1"

    /// Newest-first; at most `limit` lines (default 3). Empty when no matching records.
    static func displayLines(from records: [ExchangeAuditRecord], limit: Int = 3) -> [String] {
        let filtered = records.filter { $0.metadata[traceKindKey] == traceKindValue }
        let sorted = filtered.sorted { $0.createdAt > $1.createdAt }
        return sorted.prefix(limit).map { displayLine(for: $0) }
    }

    static func displayLine(for record: ExchangeAuditRecord) -> String {
        let m = record.metadata
        let queued = (m["queued"] ?? "").lowercased() == "true"
        if queued {
            return appendLaneIfNeeded("Autonomous send queued", metadata: m)
        }

        let skip = m["skip_reason"]
        let base: String
        switch skip {
        case "not_auto_respond_action":
            base = "Autonomous send skipped · Not an auto-response action"
        case "send_eligibility_denied":
            base = "Autonomous send skipped · Send eligibility denied"
        case "agency_autonomy_permit_denied":
            base = "Autonomous send skipped · Autonomy permit denied"
        case "queue_approved_outbound_failed":
            base = "Autonomous send failed · Queue error"
        default:
            if skip != nil || m["error_summary"] != nil {
                base = "Autonomous send skipped"
            } else {
                base = "Autonomous send skipped"
            }
        }
        return appendLaneIfNeeded(base, metadata: m)
    }

    private static func appendLaneIfNeeded(_ line: String, metadata: [String: String]) -> String {
        guard let laneLine = friendlyLaneLabel(metadata) else { return line }
        return "\(line) · \(laneLine)"
    }

    private static func friendlyLaneLabel(_ metadata: [String: String]) -> String? {
        guard let lane = metadata["lane"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !lane.isEmpty else { return nil }

        switch lane {
        case "provider_auto_response", "queueSecondHalfAutoResponseIfEligible":
            return "Provider response"
        case "requester_outbound", "queueSecondHalfRequesterOutboundIfEligible":
            return "Requester outreach"
        case "for_you":
            return "For You"
        case "first_contact":
            return "First contact"
        default:
            let lower = lane.lowercased()
            if lower.contains("provider_auto") || lower.contains("autoresponse") {
                return "Provider response"
            }
            if lower.contains("requester") && lower.contains("outbound") {
                return "Requester outreach"
            }
            if lower.contains("for_you") || lower == "foryou" {
                return "For You"
            }
            return nil
        }
    }
}
