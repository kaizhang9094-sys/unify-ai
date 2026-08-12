# ExchangeSecondHalf

## What this module is

`ExchangeSecondHalf` is the canonical greenfield implementation of the post-match half of Unify Secretary AI.

The second half begins **after** a plausible match or inbound opportunity exists.

Its job is to turn:

- possible fit

into:

- clarified opportunity
- decision-ready framing
- commitment-safe progression
- legible outcome

This module is intentionally built in parallel to older logic. It is **not** a patch of the legacy system.

---

## Core product promise

After a match is found, both sides’ secretaries should quietly handle low-stakes coordination, preserve the user’s representation, improve the opportunity before surfacing it, and present cleaner, more meaningful decisions at the right time.

Canonical rule:

**Autonomous clarification. Human commitment.**

---

## What second half owns

This module owns the full post-match coordination layer, including:

- canonical second-half states
- requester/provider per-thread role behavior
- thread stance
- thread delta / change-aware guidance
- opportunity qualification
- structured operating memory use
- stateful bilateral representation
- decision framing
- commitment boundary classification
- next-move selection
- provider-side intake behavior
- requester-side review behavior
- draft composition
- durable second-half snapshot records
- second-half projections for UI
- second-half integration façade

This is the canonical home for:

- **what the thread means now**
- **what changed**
- **what the secretary should do next**
- **whether the human must be involved**
- **what should be shown to the user**

---

## What second half does not own

This module does **not** own:

- first-half interpretation
- first-half retrieval
- BM25/vector/RRF search
- federation identity or relay primitives
- raw transport implementation
- the old Exchange thread model
- the app-wide chat runtime
- UI view rendering itself
- old inbox / discovery / thread UI assumptions

Those systems may feed into second half or consume outputs from second half, but second half should not be polluted by them.

---

## Core capabilities

### 1. Stateful bilateral representation
Both requester-side and provider-side secretaries act as stateful representatives.

Behavior should be shaped by:

- thread priors
- user-defined secretary style
- current posture
- durable preferences and boundaries

### 2. Opportunity qualification
The secretary strengthens or downgrades opportunities over time by:

- resolving ambiguity
- identifying missing facts
- deciding whether one more clarification is worthwhile
- deciding whether the thread is strong enough to surface

### 3. Structured operating memory
The secretary reasons from durable structured facts before freeform generation, including:

- pricing
- items/services
- service areas / locations
- availability / capacity
- lead times
- policies
- exclusions
- requester constraints

### 4. Decision framing
The secretary turns thread progress into a clear recommendation packet, including:

- what is known
- what changed
- what remains uncertain
- recommendation
- tradeoffs
- next move

### 5. Commitment-safe autonomy
The secretary handles low-stakes coordination autonomously but does not silently cross:

- commitment boundaries
- obligation-bearing moves
- sensitive disclosure boundaries
- policy exceptions
- schedule commitment
- custom pricing
- legal/commercial commitment

### 6. Change-aware guidance
The secretary tracks:

- what changed
- whether risk changed
- whether readiness changed
- whether recommendation changed
- whether next step changed

### 7. Thread stance and next-move discipline
The secretary maintains a compact thread stance and uses it to guide:

- tone/posture
- urgency
- trust posture
- next move selection
- follow-up discipline
- escalation timing

---

## Role model

A node is **not** globally buyer or seller.

A node can be:

- requester in one thread
- provider in another thread
- both at the same time across different threads

So role is always **per thread**, never hardcoded globally.

Canonical second-half role enum:

- `requester`
- `provider`

---

## State machine summary

Canonical states:

- `matchFound`
- `qualifying`
- `awaitingProviderClarification`
- `awaitingRequesterClarification`
- `providerReview`
- `requesterReview`
- `decisionReady`
- `awaitingCommitmentApproval`
- `accepted`
- `declined`
- `stalled`
- `blocked`
- `expired`
- `completed`

State transitions must go through the second-half state machine rather than being scattered across UI or orchestration.

---

## Natural language vs structured execution

Users interact through natural language.

Internally, the system must reduce second-half progression into structured actions such as:

- qualifyMatch
- askClarification
- answerClarification
- requestUserInput
- autoRespond
- frameDecision
- recommendNextMove
- compareOptions
- proposeTerms
- reviseTerms
- escalateForApproval
- accept
- decline
- pause
- markBlocked
- markStalled
- complete

Rule:

**Natural language on the surface, structured moves underneath.**

---

## Next-move discipline

The secretary should always aim to answer:

- what should happen next?
- does one more clarification help?
- is the opportunity strong enough to surface?
- does the user need to decide now?
- is this blocked, stale, weak, or decision-ready?

The next move should be compact, legible, and constrained.

The system should prefer:

- one focused clarification
- one clear recommendation
- one visible next step

over open-ended looping or vague momentum.

---

## Provider-side principle

Provider-side secretary behavior should feel like a real inbound operator.

It should be able to:

- answer routine inbound questions from structured memory
- qualify inbound demand
- decline clearly out-of-scope inquiries
- ask provider user only when needed
- surface promising leads cleanly

The provider user should not be interrupted for every inbound message.

---

## Requester-side principle

Requester-side secretary behavior should feel like a real representative reviewing opportunities.

It should be able to:

- review a surfaced match
- decide what is still missing
- ask one useful clarification if needed
- decide whether to surface now
- frame the opportunity clearly for the user

The requester user should not be forced to read every intermediate exchange.

---

## Commitment boundary rule

Canonical product rule:

**Autonomous clarification. Human commitment.**

Autonomous behavior may include:

- qualification
- clarification asking
- clarification answering from known facts
- routine surface responses
- decision framing
- recommendation
- draft preparation

Human approval is required when the move becomes:

- commitment-bearing
- obligation-bearing
- sensitive disclosure
- policy exception
- custom pricing
- schedule commitment
- legal/commercial commitment

---

## Follow-up discipline

Second half should not become naggy.

Follow-up must be bounded by policy, including:

- follow-up count
- repeated clarification limit
- stale thresholds
- duplicate follow-up avoidance
- preference for surfacing rather than endless nudging

---

## Memory ownership

Second half owns its own compact memory inputs, including:

- structured operating memory
- secretary style profile
- compact thread priors

These are separate from raw thread logs.

Rule:

**Do not replay full thread history when compact priors are enough.**

---

## Projection ownership

Second half produces UI-facing projections.

These projections are the canonical shape the UI should render for post-match behavior, including:

- top-level thread projection
- decision packet
- provider inbox card
- requester review card
- next move view model

This module owns the meaning of these projections, not the rendering layer itself.

---

## Persistence ownership

Second half owns second-half-specific durable record contracts, including:

- snapshot record
- stance record
- decision frame record
- operating memory record
- thread delta record

These should remain separate from legacy persistence shapes.

---

## Debug / trace policy

Debug logging should exist in:

- orchestration
- decision-heavy engines
- integration boundaries

Debug logging should **not** be spread through pure model files.

Rule:

**Log decisions, transitions, and boundaries — not data definitions.**

---

## Build rule

This module is a **greenfield parallel implementation**.

Rules:

- no patchwork
- no drifting back into old second-half logic
- do not retrofit old assumptions into the new core
- build this path cleanly first
- integrate through adapters
- cut over later
- scrub incompatible old logic only after this path works

Canonical summary:

**Build parallel first, cut over later, then purge incompatible old logic.**

---

## Current folder map

```text
ExchangeSecondHalf/
├── Models/
├── Engine/
├── Memory/
├── Framing/
├── Policy/
├── Orchestration/
├── Persistence/
├── Projections/
├── Integration/
└── README_SecondHalf.md
