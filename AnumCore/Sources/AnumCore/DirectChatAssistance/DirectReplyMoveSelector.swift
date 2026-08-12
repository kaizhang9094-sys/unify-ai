import Foundation

/// Deterministic strategic move selection for direct-chat reply suggestions (no LLM).
public enum DirectReplyMoveSelector {
    public static func select(
        intent: DirectReplyLatestIntent,
        state: DirectReplyConversationState,
        contactBrief: DirectReplyContactBrief?
    ) -> DirectReplySelectedMove {
        let requiresCaution = contactBrief?.stakes == .high || contactBrief?.stakes == .medium

        let selected: DirectReplySelectedMove
        switch intent.kind {
        case .invitation:
            selected = DirectReplySelectedMove(
                kind: .acceptAndAskTime,
                reason: "Latest message proposes a plan; accept, decline, or ask for missing details such as time.",
                constraints: moveSpecificConstraints(for: .acceptAndAskTime, state: state, intent: intent),
                requiresCaution: requiresCaution
            )

        case .statusCheck:
            selected = DirectReplySelectedMove(
                kind: .answerStatusWithNextStep,
                reason: "Latest message asks for status; answer current status and the next step.",
                constraints: moveSpecificConstraints(for: .answerStatusWithNextStep, state: state, intent: intent),
                requiresCaution: requiresCaution
            )

        case .delayConfirmation, .schedulingConfirmation:
            selected = DirectReplySelectedMove(
                kind: .reassure,
                reason: "Latest message checks whether a timing change is okay; confirm, reassure, or object briefly.",
                constraints: moveSpecificConstraints(for: .reassure, state: state, intent: intent),
                requiresCaution: requiresCaution
            )

        case .choiceQuestion:
            selected = DirectReplySelectedMove(
                kind: .choosePreference,
                reason: "Latest message asks to choose; pick one option or state a preference directly.",
                constraints: moveSpecificConstraints(for: .choosePreference, state: state, intent: intent),
                requiresCaution: requiresCaution
            )

        case .acknowledgement:
            selected = DirectReplySelectedMove(
                kind: .acknowledgeAndContinue,
                reason: "Latest message is a brief thanks or acknowledgement; respond naturally and keep momentum.",
                constraints: moveSpecificConstraints(for: .acknowledgeAndContinue, state: state, intent: intent),
                requiresCaution: requiresCaution
            )

        case .greeting:
            selected = DirectReplySelectedMove(
                kind: .acknowledgeAndContinue,
                reason: "Latest message is a greeting; greet back briefly and invite the next topic.",
                constraints: moveSpecificConstraints(for: .acknowledgeAndContinue, state: state, intent: intent),
                requiresCaution: requiresCaution
            )

        case .closing:
            selected = DirectReplySelectedMove(
                kind: .closeWarmly,
                reason: "Latest message closes or winds down the thread; respond warmly and briefly.",
                constraints: moveSpecificConstraints(for: .closeWarmly, state: state, intent: intent),
                requiresCaution: requiresCaution
            )

        case .request:
            selected = DirectReplySelectedMove(
                kind: .askClarifyingQuestion,
                reason: "Latest message is a request; confirm, decline, or ask one clarifying question.",
                constraints: moveSpecificConstraints(for: .askClarifyingQuestion, state: state, intent: intent),
                requiresCaution: requiresCaution
            )

        case .unknown:
            if state.openItems.contains(where: { $0.lowercased().contains("completed") || $0.lowercased().contains("sent") }) {
                selected = DirectReplySelectedMove(
                    kind: .answerStatusWithNextStep,
                    reason: "Conversation has an open status item; answer current status and next step.",
                    constraints: moveSpecificConstraints(for: .answerStatusWithNextStep, state: state, intent: intent),
                    requiresCaution: requiresCaution
                )
            } else {
                selected = DirectReplySelectedMove(
                    kind: .askClarifyingQuestion,
                    reason: "Latest message intent is unclear; ask one short clarifying question or answer narrowly.",
                    constraints: moveSpecificConstraints(for: .askClarifyingQuestion, state: state, intent: intent),
                    requiresCaution: requiresCaution
                )
            }
        }

        return DirectReplySelectedMove(
            kind: selected.kind,
            reason: selected.reason,
            constraints: baseConstraints() + selected.constraints,
            requiresCaution: selected.requiresCaution
        )
    }

    static func baseConstraints() -> [String] {
        [
            "Do not echo the inbound phrasing.",
            "Do not answer older messages.",
            "Do not reuse previous local messages as new content.",
            "Do not choose a different conversational move.",
            "Write as the local user replying to the remote contact.",
            "Do not change speaker perspective.",
        ]
    }

    static func moveSpecificConstraints(
        for kind: DirectReplySelectedMove.Kind,
        state: DirectReplyConversationState,
        intent: DirectReplyLatestIntent
    ) -> [String] {
        switch kind {
        case .acceptAndAskTime:
            return [
                "If accepting an invitation with a proposed day or window, do not ask whether that same proposed day or window works.",
                "Ask only for missing exact details such as exact time or place, or confirm availability.",
                "Good shape: Saturday morning works — what time were you thinking?",
            ]
        case .answerStatusWithNextStep:
            if state.completionConfirmed {
                return ["State confirms completion; you may answer accordingly without inventing new facts."]
            }
            return [
                "Do not claim completion unless conversationState confirms completion.",
                "If completion is unknown or not confirmed, say not yet, still working, or will send shortly.",
                "Avoid I've got it ready, it's ready, or I've sent it unless established facts confirm completion.",
                "Do not repeat an old promise verbatim.",
            ]
        case .reassure:
            return [
                "The remote contact is the one reporting the delay unless state explicitly says the local user is delayed.",
                "Do not say I'm running late unless the local user is the one who is late.",
                "Reply from the local user's perspective to reassure or object.",
                "Confirm whether the delay is okay; do not restate the delay as a question.",
                "Good shape: No worries, still good. or All good, see you soon.",
            ]
        case .choosePreference:
            return [
                "Pick one option directly.",
                "Do not ask the same choice back unless the selected move is askClarifyingQuestion.",
                "Good shape: Tacos sounds good to me.",
            ]
        case .acknowledgeAndContinue:
            return ["Keep the reply brief and forward-looking."]
        case .closeWarmly:
            return ["Close warmly without opening a new topic."]
        case .askClarifyingQuestion:
            return ["Ask at most one short clarifying question if needed."]
        case .redirect:
            return ["Redirect briefly without changing the selected move."]
        case .hold:
            return ["Hold briefly without making new commitments."]
        case .unknown:
            _ = intent
            return []
        }
    }
}
