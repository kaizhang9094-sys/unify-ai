import Foundation

public enum DirectChatReplySuggestionParser {
    public static func parse(raw: String) -> ExchangeModels.DirectReplySuggestionOutput? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let jsonSlice: String
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") {
            jsonSlice = String(trimmed[start...end])
        } else {
            return nil
        }
        guard let data = jsonSlice.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(DirectChatReplySuggestionModels.Payload.self, from: data) else {
            return nil
        }
        let reply = decoded.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else { return nil }
        return ExchangeModels.DirectReplySuggestionOutput(
            reply: String(reply.prefix(900)),
            reason: nil,
            safety: nil,
            requiresApproval: true
        )
    }
}
