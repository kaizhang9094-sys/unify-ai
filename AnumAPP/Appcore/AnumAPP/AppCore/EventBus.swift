import Foundation
import Combine

enum TurnEvent: Sendable {
    case turnStarted(turnId: UUID)
    case promptBuilt(turnId: UUID, chars: Int)
    case chunk(turnId: UUID, chars: Int)
    case turnFinished(turnId: UUID, outputChars: Int)
    case turnError(turnId: UUID, message: String)
}

@MainActor
final class EventBus: ObservableObject {
    static let shared = EventBus()

    @Published private(set) var lastEventDescription: String = "—"

    func emit(_ e: TurnEvent) {
        let s: String
        switch e {
        case .turnStarted(let id):
            s = "turnStarted \(id)"
        case .promptBuilt(let id, let chars):
            s = "promptBuilt \(id) chars=\(chars)"
        case .chunk(let id, let chars):
            s = "chunk \(id) chars=\(chars)"
        case .turnFinished(let id, let out):
            s = "turnFinished \(id) outChars=\(out)"
        case .turnError(let id, let msg):
            s = "turnError \(id) \(msg)"
        }
        lastEventDescription = s
        #if DEBUG
        print("[EventBus] \(s)")
        #endif
    }
}
