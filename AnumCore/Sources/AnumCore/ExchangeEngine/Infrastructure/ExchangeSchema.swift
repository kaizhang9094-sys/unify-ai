import Foundation

public enum ExchangeSchema {
    public static let currentVersion: Int = 13

    public static let migrations: [Migration] = [
        Migration(
            version: 1,
            statements: [
                """
                CREATE TABLE IF NOT EXISTS exchange_schema_version (
                    version INTEGER NOT NULL PRIMARY KEY,
                    applied_at TEXT NOT NULL
                );
                """,

                """
                CREATE TABLE IF NOT EXISTS exchange_failures (
                    id TEXT PRIMARY KEY NOT NULL,
                    thread_id TEXT,
                    created_at TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    severity TEXT NOT NULL,
                    summary TEXT NOT NULL,
                    what_happened TEXT NOT NULL,
                    what_did_not_happen TEXT NOT NULL,
                    external_effect_json BLOB NOT NULL,
                    recommended_next_step_json BLOB NOT NULL,
                    reason_code TEXT,
                    technical_details TEXT,
                    is_retryable INTEGER NOT NULL,
                    json_snapshot BLOB NOT NULL
                );
                """,

                """
                CREATE TABLE IF NOT EXISTS exchange_threads (
                    id TEXT PRIMARY KEY NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    revision INTEGER NOT NULL DEFAULT 1,
                    mode TEXT NOT NULL,
                    state_key TEXT NOT NULL,
                    title TEXT NOT NULL,
                    selected_counterparty_id TEXT,
                    latest_failure_id TEXT,
                    visible_summary TEXT,
                    requires_human_decision INTEGER NOT NULL DEFAULT 0,
                    outcome_status TEXT,
                    intent_json BLOB NOT NULL,
                    posture_json BLOB NOT NULL,
                    approval_json BLOB,
                    delivery_json BLOB,
                    outcome_json BLOB,
                    metadata_json BLOB NOT NULL,
                    json_snapshot BLOB NOT NULL,
                    FOREIGN KEY(latest_failure_id) REFERENCES exchange_failures(id) ON DELETE SET NULL
                );
                """,

                """
                CREATE TABLE IF NOT EXISTS exchange_turns (
                    id TEXT PRIMARY KEY NOT NULL,
                    thread_id TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    actor TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    summary TEXT NOT NULL,
                    detail TEXT,
                    visibility TEXT NOT NULL,
                    external_reference TEXT,
                    failure_id TEXT,
                    metadata_json BLOB NOT NULL,
                    json_snapshot BLOB NOT NULL,
                    FOREIGN KEY(thread_id) REFERENCES exchange_threads(id) ON DELETE CASCADE,
                    FOREIGN KEY(failure_id) REFERENCES exchange_failures(id) ON DELETE SET NULL
                );
                """,

                """
                CREATE TABLE IF NOT EXISTS exchange_approvals (
                    id TEXT PRIMARY KEY NOT NULL,
                    thread_id TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    revision INTEGER NOT NULL DEFAULT 1,
                    status TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    draft_id TEXT,
                    summary TEXT NOT NULL,
                    rationale TEXT,
                    expires_at TEXT,
                    decided_at TEXT,
                    decision_note TEXT,
                    requested_action_json BLOB NOT NULL,
                    metadata_json BLOB NOT NULL,
                    json_snapshot BLOB NOT NULL,
                    FOREIGN KEY(thread_id) REFERENCES exchange_threads(id) ON DELETE CASCADE
                );
                """,

                """
                CREATE TABLE IF NOT EXISTS exchange_drafts (
                    id TEXT PRIMARY KEY NOT NULL,
                    thread_id TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    revision INTEGER NOT NULL DEFAULT 1,
                    status TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    audience TEXT NOT NULL,
                    subject TEXT,
                    body TEXT NOT NULL,
                    strategy_note TEXT,
                    target_counterparty_id TEXT,
                    supersedes_draft_id TEXT,
                    sent_external_reference TEXT,
                    posture_json BLOB NOT NULL,
                    metadata_json BLOB NOT NULL,
                    json_snapshot BLOB NOT NULL,
                    FOREIGN KEY(thread_id) REFERENCES exchange_threads(id) ON DELETE CASCADE
                );
                """,

                """
                CREATE TABLE IF NOT EXISTS exchange_outcomes (
                    id TEXT PRIMARY KEY NOT NULL,
                    thread_id TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    status TEXT NOT NULL,
                    category TEXT NOT NULL,
                    summary TEXT NOT NULL,
                    what_happened TEXT NOT NULL,
                    what_did_not_happen TEXT NOT NULL,
                    recommended_next_step TEXT,
                    failure_id TEXT,
                    external_effect_json BLOB NOT NULL,
                    metadata_json BLOB NOT NULL,
                    json_snapshot BLOB NOT NULL,
                    FOREIGN KEY(thread_id) REFERENCES exchange_threads(id) ON DELETE CASCADE,
                    FOREIGN KEY(failure_id) REFERENCES exchange_failures(id) ON DELETE SET NULL
                );
                """,

                """
                CREATE TABLE IF NOT EXISTS exchange_counterparties (
                    id TEXT PRIMARY KEY NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    revision INTEGER NOT NULL DEFAULT 1,
                    kind TEXT NOT NULL,
                    display_name TEXT NOT NULL,
                    handle TEXT,
                    bio TEXT,
                    trust_level TEXT NOT NULL,
                    trust_summary TEXT,
                    completed_threads INTEGER NOT NULL DEFAULT 0,
                    successful_threads INTEGER NOT NULL DEFAULT 0,
                    status TEXT NOT NULL,
                    source_json BLOB NOT NULL,
                    identity_json BLOB,
                    location_json BLOB,
                    metadata_json BLOB NOT NULL,
                    json_snapshot BLOB NOT NULL
                );
                """,

                """
                CREATE TABLE IF NOT EXISTS exchange_counterparty_tags (
                    counterparty_id TEXT NOT NULL,
                    tag TEXT NOT NULL,
                    PRIMARY KEY(counterparty_id, tag),
                    FOREIGN KEY(counterparty_id) REFERENCES exchange_counterparties(id) ON DELETE CASCADE
                );
                """,

                """
                CREATE TABLE IF NOT EXISTS exchange_counterparty_capabilities (
                    id TEXT PRIMARY KEY NOT NULL,
                    counterparty_id TEXT NOT NULL,
                    label TEXT NOT NULL,
                    category TEXT,
                    notes TEXT,
                    FOREIGN KEY(counterparty_id) REFERENCES exchange_counterparties(id) ON DELETE CASCADE
                );
                """,

                """
                CREATE TABLE IF NOT EXISTS exchange_contact_routes (
                    id TEXT PRIMARY KEY NOT NULL,
                    counterparty_id TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    value TEXT NOT NULL,
                    is_preferred INTEGER NOT NULL DEFAULT 0,
                    FOREIGN KEY(counterparty_id) REFERENCES exchange_counterparties(id) ON DELETE CASCADE
                );
                """,

                """
                CREATE TABLE IF NOT EXISTS exchange_matches (
                    id TEXT PRIMARY KEY NOT NULL,
                    thread_id TEXT NOT NULL,
                    counterparty_id TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    status TEXT NOT NULL,
                    strength TEXT NOT NULL,
                    score REAL NOT NULL,
                    recommendation TEXT,
                    fit_json BLOB NOT NULL,
                    metadata_json BLOB NOT NULL,
                    json_snapshot BLOB NOT NULL,
                    FOREIGN KEY(thread_id) REFERENCES exchange_threads(id) ON DELETE CASCADE,
                    FOREIGN KEY(counterparty_id) REFERENCES exchange_counterparties(id) ON DELETE CASCADE
                );
                """,

                """
                CREATE TABLE IF NOT EXISTS exchange_match_reasons (
                    id TEXT PRIMARY KEY NOT NULL,
                    match_id TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    summary TEXT NOT NULL,
                    FOREIGN KEY(match_id) REFERENCES exchange_matches(id) ON DELETE CASCADE
                );
                """,

                """
                CREATE TABLE IF NOT EXISTS exchange_match_cautions (
                    id TEXT PRIMARY KEY NOT NULL,
                    match_id TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    summary TEXT NOT NULL,
                    FOREIGN KEY(match_id) REFERENCES exchange_matches(id) ON DELETE CASCADE
                );
                """,

                """
                CREATE TABLE IF NOT EXISTS exchange_artifacts (
                    id TEXT PRIMARY KEY NOT NULL,
                    thread_id TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    revision INTEGER NOT NULL DEFAULT 1,
                    kind TEXT NOT NULL,
                    status TEXT NOT NULL,
                    title TEXT NOT NULL,
                    summary TEXT,
                    visibility TEXT NOT NULL,
                    payload_json BLOB NOT NULL,
                    metadata_json BLOB NOT NULL,
                    json_snapshot BLOB NOT NULL,
                    FOREIGN KEY(thread_id) REFERENCES exchange_threads(id) ON DELETE CASCADE
                );
                """,

                "CREATE INDEX IF NOT EXISTS idx_exchange_threads_updated_at ON exchange_threads(updated_at DESC);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_threads_state_key ON exchange_threads(state_key);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_threads_requires_human_decision ON exchange_threads(requires_human_decision);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_threads_selected_counterparty_id ON exchange_threads(selected_counterparty_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_threads_latest_failure_id ON exchange_threads(latest_failure_id);",

                "CREATE INDEX IF NOT EXISTS idx_exchange_turns_thread_id_created_at ON exchange_turns(thread_id, created_at DESC);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_turns_kind ON exchange_turns(kind);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_turns_failure_id ON exchange_turns(failure_id);",

                "CREATE INDEX IF NOT EXISTS idx_exchange_approvals_thread_id_updated_at ON exchange_approvals(thread_id, updated_at DESC);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_approvals_status ON exchange_approvals(status);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_approvals_draft_id ON exchange_approvals(draft_id);",

                "CREATE INDEX IF NOT EXISTS idx_exchange_drafts_thread_id_updated_at ON exchange_drafts(thread_id, updated_at DESC);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_drafts_status ON exchange_drafts(status);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_drafts_target_counterparty_id ON exchange_drafts(target_counterparty_id);",

                "CREATE INDEX IF NOT EXISTS idx_exchange_outcomes_thread_id_created_at ON exchange_outcomes(thread_id, created_at DESC);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_outcomes_status ON exchange_outcomes(status);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_outcomes_failure_id ON exchange_outcomes(failure_id);",

                "CREATE INDEX IF NOT EXISTS idx_exchange_failures_thread_id_created_at ON exchange_failures(thread_id, created_at DESC);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_failures_kind ON exchange_failures(kind);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_failures_reason_code ON exchange_failures(reason_code);",

                "CREATE INDEX IF NOT EXISTS idx_exchange_counterparties_display_name ON exchange_counterparties(display_name);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_counterparties_status ON exchange_counterparties(status);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_counterparties_trust_level ON exchange_counterparties(trust_level);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_counterparty_tags_tag ON exchange_counterparty_tags(tag);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_counterparty_capabilities_counterparty_id ON exchange_counterparty_capabilities(counterparty_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_contact_routes_counterparty_id ON exchange_contact_routes(counterparty_id);",

                "CREATE INDEX IF NOT EXISTS idx_exchange_matches_thread_id_created_at ON exchange_matches(thread_id, created_at DESC);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_matches_counterparty_id ON exchange_matches(counterparty_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_matches_status ON exchange_matches(status);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_matches_strength_score ON exchange_matches(strength, score DESC);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_match_reasons_match_id ON exchange_match_reasons(match_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_match_cautions_match_id ON exchange_match_cautions(match_id);",

                "CREATE INDEX IF NOT EXISTS idx_exchange_artifacts_thread_id_updated_at ON exchange_artifacts(thread_id, updated_at DESC);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_artifacts_kind ON exchange_artifacts(kind);"
            ]
        ),

        Migration(
            version: 2,
            statements: [
                """
                CREATE TABLE IF NOT EXISTS exchange_trust_edges (
                    id TEXT PRIMARY KEY NOT NULL,
                    source_node_id TEXT NOT NULL,
                    target_node_id TEXT NOT NULL,
                    relationship_type TEXT NOT NULL,
                    trust_level TEXT NOT NULL,
                    visibility TEXT NOT NULL,
                    source_kind TEXT NOT NULL,
                    note TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    last_confirmed_at TEXT,
                    revoked_at TEXT,
                    metadata_json BLOB NOT NULL,
                    json_snapshot BLOB NOT NULL
                );
                """,

                """
                CREATE TABLE IF NOT EXISTS exchange_trust_edge_scopes (
                    trust_edge_id TEXT NOT NULL,
                    scope TEXT NOT NULL,
                    PRIMARY KEY(trust_edge_id, scope),
                    FOREIGN KEY(trust_edge_id) REFERENCES exchange_trust_edges(id) ON DELETE CASCADE
                );
                """,

                """
                CREATE TABLE IF NOT EXISTS exchange_trust_evidence (
                    id TEXT PRIMARY KEY NOT NULL,
                    trust_edge_id TEXT NOT NULL,
                    type TEXT NOT NULL,
                    weight REAL NOT NULL,
                    thread_id TEXT,
                    related_node_id TEXT,
                    summary TEXT,
                    note TEXT,
                    recorded_at TEXT NOT NULL,
                    metadata_json BLOB NOT NULL,
                    json_snapshot BLOB NOT NULL,
                    FOREIGN KEY(trust_edge_id) REFERENCES exchange_trust_edges(id) ON DELETE CASCADE,
                    FOREIGN KEY(thread_id) REFERENCES exchange_threads(id) ON DELETE SET NULL
                );
                """,

                "CREATE UNIQUE INDEX IF NOT EXISTS idx_exchange_trust_edges_source_target_unique ON exchange_trust_edges(source_node_id, target_node_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_trust_edges_source_node_id ON exchange_trust_edges(source_node_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_trust_edges_target_node_id ON exchange_trust_edges(target_node_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_trust_edges_relationship_type ON exchange_trust_edges(relationship_type);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_trust_edges_trust_level ON exchange_trust_edges(trust_level);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_trust_edges_visibility ON exchange_trust_edges(visibility);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_trust_edges_source_kind ON exchange_trust_edges(source_kind);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_trust_edges_revoked_at ON exchange_trust_edges(revoked_at);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_trust_edges_updated_at ON exchange_trust_edges(updated_at DESC);",

                "CREATE INDEX IF NOT EXISTS idx_exchange_trust_edge_scopes_scope ON exchange_trust_edge_scopes(scope);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_trust_edge_scopes_trust_edge_id ON exchange_trust_edge_scopes(trust_edge_id);",

                "CREATE INDEX IF NOT EXISTS idx_exchange_trust_evidence_trust_edge_id_recorded_at ON exchange_trust_evidence(trust_edge_id, recorded_at DESC);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_trust_evidence_type ON exchange_trust_evidence(type);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_trust_evidence_thread_id ON exchange_trust_evidence(thread_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_trust_evidence_related_node_id ON exchange_trust_evidence(related_node_id);"
            ]
        ),

        Migration(
            version: 3,
            statements: [
                """
                CREATE TABLE IF NOT EXISTS exchange_outbox_items (
                    id TEXT PRIMARY KEY NOT NULL,
                    thread_id TEXT NOT NULL,
                    draft_id TEXT NOT NULL,
                    approval_id TEXT,
                    target_node_id TEXT NOT NULL,
                    envelope_id TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    is_active INTEGER NOT NULL DEFAULT 1,
                    delivery_phase TEXT NOT NULL,
                    delivery_priority TEXT NOT NULL,
                    delivery_note TEXT,
                    delivery_external_effect_json BLOB NOT NULL,
                    queued_at TEXT,
                    first_attempt_at TEXT,
                    last_attempt_at TEXT,
                    sent_at TEXT,
                    acknowledged_at TEXT,
                    cancelled_at TEXT,
                    failed_at TEXT,
                    deferred_until TEXT,
                    attempt_count INTEGER NOT NULL DEFAULT 0,
                    last_error_code TEXT,
                    last_external_reference TEXT,
                    relay_route_summary TEXT,
                    policy_json BLOB NOT NULL,
                    payload_summary TEXT NOT NULL,
                    metadata_json BLOB NOT NULL,
                    json_snapshot BLOB NOT NULL,
                    FOREIGN KEY(thread_id) REFERENCES exchange_threads(id) ON DELETE CASCADE,
                    FOREIGN KEY(draft_id) REFERENCES exchange_drafts(id) ON DELETE CASCADE,
                    FOREIGN KEY(approval_id) REFERENCES exchange_approvals(id) ON DELETE SET NULL
                );
                """,

                """
                CREATE TABLE IF NOT EXISTS exchange_inbox_items (
                    id TEXT PRIMARY KEY NOT NULL,
                    envelope_id TEXT NOT NULL,
                    thread_id TEXT,
                    sender_node_id TEXT,
                    sender_display_name TEXT,
                    received_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    sequence_number INTEGER,
                    parent_envelope_id TEXT,
                    sender_timestamp TEXT,
                    compatibility_kind TEXT NOT NULL,
                    compatibility_value TEXT,
                    processing_state TEXT NOT NULL,
                    visible_summary TEXT NOT NULL,
                    metadata_json BLOB NOT NULL,
                    json_snapshot BLOB NOT NULL,
                    FOREIGN KEY(thread_id) REFERENCES exchange_threads(id) ON DELETE SET NULL
                );
                """,

                """
                CREATE TABLE IF NOT EXISTS exchange_audit_records (
                    id TEXT PRIMARY KEY NOT NULL,
                    created_at TEXT NOT NULL,
                    thread_id TEXT,
                    direction TEXT NOT NULL,
                    category TEXT NOT NULL,
                    actor TEXT NOT NULL,
                    envelope_id TEXT,
                    outbox_item_id TEXT,
                    inbox_item_id TEXT,
                    summary TEXT NOT NULL,
                    detail TEXT,
                    external_effect_json BLOB NOT NULL,
                    related_node_id TEXT,
                    related_display_name TEXT,
                    metadata_json BLOB NOT NULL,
                    json_snapshot BLOB NOT NULL,
                    FOREIGN KEY(thread_id) REFERENCES exchange_threads(id) ON DELETE SET NULL,
                    FOREIGN KEY(outbox_item_id) REFERENCES exchange_outbox_items(id) ON DELETE SET NULL,
                    FOREIGN KEY(inbox_item_id) REFERENCES exchange_inbox_items(id) ON DELETE SET NULL
                );
                """,

                "CREATE UNIQUE INDEX IF NOT EXISTS idx_exchange_outbox_items_envelope_id_unique ON exchange_outbox_items(envelope_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_outbox_items_thread_id_updated_at ON exchange_outbox_items(thread_id, updated_at DESC);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_outbox_items_draft_id ON exchange_outbox_items(draft_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_outbox_items_approval_id ON exchange_outbox_items(approval_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_outbox_items_target_node_id ON exchange_outbox_items(target_node_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_outbox_items_delivery_phase ON exchange_outbox_items(delivery_phase);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_outbox_items_is_active ON exchange_outbox_items(is_active);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_outbox_items_created_at ON exchange_outbox_items(created_at DESC);",

                "CREATE UNIQUE INDEX IF NOT EXISTS idx_exchange_inbox_items_envelope_id_unique ON exchange_inbox_items(envelope_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_inbox_items_thread_id_received_at ON exchange_inbox_items(thread_id, received_at DESC);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_inbox_items_sender_node_id ON exchange_inbox_items(sender_node_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_inbox_items_processing_state ON exchange_inbox_items(processing_state);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_inbox_items_compatibility_kind ON exchange_inbox_items(compatibility_kind);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_inbox_items_received_at ON exchange_inbox_items(received_at DESC);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_inbox_items_sequence_number ON exchange_inbox_items(sequence_number);",

                "CREATE INDEX IF NOT EXISTS idx_exchange_audit_records_thread_id_created_at ON exchange_audit_records(thread_id, created_at DESC);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_audit_records_direction ON exchange_audit_records(direction);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_audit_records_category ON exchange_audit_records(category);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_audit_records_envelope_id ON exchange_audit_records(envelope_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_audit_records_related_node_id ON exchange_audit_records(related_node_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_audit_records_created_at ON exchange_audit_records(created_at DESC);"
            ]
        ),

        Migration(
            version: 4,
            statements: [
                "ALTER TABLE exchange_turns ADD COLUMN visibility_mask INTEGER NOT NULL DEFAULT 1;",
                "ALTER TABLE exchange_artifacts ADD COLUMN visibility_mask INTEGER NOT NULL DEFAULT 1;",

                "ALTER TABLE exchange_trust_edges ADD COLUMN propagation TEXT;",
                "UPDATE exchange_trust_edges SET propagation = visibility WHERE propagation IS NULL;",
                "CREATE INDEX IF NOT EXISTS idx_exchange_trust_edges_propagation ON exchange_trust_edges(propagation);",

                "ALTER TABLE exchange_trust_evidence ADD COLUMN related_counterparty_id TEXT;",
                "UPDATE exchange_trust_evidence SET related_counterparty_id = related_node_id WHERE related_counterparty_id IS NULL;",
                "CREATE INDEX IF NOT EXISTS idx_exchange_trust_evidence_related_counterparty_id ON exchange_trust_evidence(related_counterparty_id);",

                "CREATE INDEX IF NOT EXISTS idx_exchange_threads_mode_state_updated_at ON exchange_threads(mode, state_key, updated_at DESC);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_outbox_items_phase_active_updated_at ON exchange_outbox_items(delivery_phase, is_active, updated_at DESC);"
            ]
        ),

        Migration(
            version: 5,
            statements: [
                """
                CREATE TABLE IF NOT EXISTS exchange_sync_state (
                    id TEXT PRIMARY KEY NOT NULL,
                    inbound_checkpoint TEXT,
                    last_inbound_sync_at TEXT,
                    last_outbound_flush_at TEXT,
                    last_reconcile_at TEXT,
                    last_successful_sync_at TEXT,
                    last_attempt_at TEXT,
                    backoff_until TEXT,
                    consecutive_failure_count INTEGER NOT NULL DEFAULT 0,
                    last_error_summary TEXT,
                    last_error_domain TEXT,
                    active_run_id TEXT,
                    updated_at TEXT NOT NULL,
                    json_snapshot BLOB NOT NULL
                );
                """,

                "CREATE INDEX IF NOT EXISTS idx_exchange_sync_state_last_successful_sync_at ON exchange_sync_state(last_successful_sync_at DESC);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_sync_state_backoff_until ON exchange_sync_state(backoff_until);"
            ]
        ),

        Migration(
            version: 6,
            statements: [
                "ALTER TABLE exchange_threads ADD COLUMN selected_public_profile_id TEXT;",
                "ALTER TABLE exchange_threads ADD COLUMN selected_offer_id TEXT;",

                """
                CREATE TABLE IF NOT EXISTS exchange_public_profiles (
                    id TEXT PRIMARY KEY NOT NULL,
                    node_id TEXT NOT NULL,
                    counterparty_id TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    revision INTEGER NOT NULL DEFAULT 1,
                    display_name TEXT,
                    headline TEXT,
                    summary TEXT,
                    visibility TEXT NOT NULL,
                    availability TEXT NOT NULL,
                    interests_json BLOB NOT NULL,
                    offers_json BLOB NOT NULL,
                    open_to_json BLOB NOT NULL,
                    excluded_topics_json BLOB NOT NULL,
                    activity_tags_json BLOB NOT NULL,
                    region_tags_json BLOB NOT NULL,
                    semantic_json BLOB NOT NULL,
                    reachability_json BLOB NOT NULL,
                    approach_json BLOB NOT NULL,
                    metadata_json BLOB NOT NULL,
                    json_snapshot BLOB NOT NULL,
                    FOREIGN KEY(counterparty_id) REFERENCES exchange_counterparties(id) ON DELETE SET NULL
                );
                """,

                """
                CREATE TABLE IF NOT EXISTS exchange_publication_state (
                    public_profile_id TEXT PRIMARY KEY NOT NULL,
                    status TEXT NOT NULL,
                    published_at TEXT,
                    last_attempt_at TEXT,
                    last_success_at TEXT,
                    last_failure_summary TEXT,
                    last_remote_profile_id TEXT,
                    last_remote_offer_ids_json BLOB NOT NULL,
                    metadata_json BLOB NOT NULL,
                    json_snapshot BLOB NOT NULL,
                    FOREIGN KEY(public_profile_id) REFERENCES exchange_public_profiles(id) ON DELETE CASCADE
                );
                """,

                """
                CREATE TABLE IF NOT EXISTS exchange_offers (
                    id TEXT PRIMARY KEY NOT NULL,
                    counterparty_id TEXT,
                    public_profile_id TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    revision INTEGER NOT NULL DEFAULT 1,
                    title TEXT NOT NULL,
                    summary TEXT,
                    details TEXT,
                    category TEXT,
                    fulfillment_mode TEXT NOT NULL,
                    visibility TEXT NOT NULL,
                    status TEXT NOT NULL,
                    price_summary TEXT,
                    currency_code TEXT,
                    region_summary TEXT,
                    tags_json BLOB NOT NULL,
                    metadata_json BLOB NOT NULL,
                    json_snapshot BLOB NOT NULL,
                    FOREIGN KEY(counterparty_id) REFERENCES exchange_counterparties(id) ON DELETE SET NULL,
                    FOREIGN KEY(public_profile_id) REFERENCES exchange_public_profiles(id) ON DELETE CASCADE
                );
                """,

                "CREATE INDEX IF NOT EXISTS idx_exchange_threads_selected_public_profile_id ON exchange_threads(selected_public_profile_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_threads_selected_offer_id ON exchange_threads(selected_offer_id);",

                "CREATE INDEX IF NOT EXISTS idx_exchange_public_profiles_node_id ON exchange_public_profiles(node_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_public_profiles_counterparty_id ON exchange_public_profiles(counterparty_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_public_profiles_visibility ON exchange_public_profiles(visibility);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_public_profiles_availability ON exchange_public_profiles(availability);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_public_profiles_updated_at ON exchange_public_profiles(updated_at DESC);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_public_profiles_visibility_availability_updated_at ON exchange_public_profiles(visibility, availability, updated_at DESC);",

                "CREATE INDEX IF NOT EXISTS idx_exchange_publication_state_status ON exchange_publication_state(status);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_publication_state_last_success_at ON exchange_publication_state(last_success_at DESC);",

                "CREATE INDEX IF NOT EXISTS idx_exchange_offers_counterparty_id ON exchange_offers(counterparty_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_offers_public_profile_id ON exchange_offers(public_profile_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_offers_status ON exchange_offers(status);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_offers_visibility ON exchange_offers(visibility);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_offers_category ON exchange_offers(category);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_offers_updated_at ON exchange_offers(updated_at DESC);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_offers_profile_status_updated_at ON exchange_offers(public_profile_id, status, updated_at DESC);"
            ]
        ),

        Migration(
            version: 7,
            statements: [
                "ALTER TABLE exchange_publication_state ADD COLUMN is_dirty INTEGER NOT NULL DEFAULT 0;",
                "ALTER TABLE exchange_publication_state ADD COLUMN last_local_mutation_at TEXT;",
                "ALTER TABLE exchange_publication_state ADD COLUMN last_published_fingerprint TEXT;",

                "UPDATE exchange_publication_state SET is_dirty = 1 WHERE status IN ('draft', 'failed');",
                "UPDATE exchange_publication_state SET is_dirty = 0 WHERE status IN ('published', 'paused', 'archived');",

                "CREATE INDEX IF NOT EXISTS idx_exchange_publication_state_is_dirty ON exchange_publication_state(is_dirty);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_publication_state_status_dirty ON exchange_publication_state(status, is_dirty);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_publication_state_last_local_mutation_at ON exchange_publication_state(last_local_mutation_at DESC);"
            ]
        ),

        Migration(
            version: 8,
            statements: [
                "DROP INDEX IF EXISTS idx_exchange_offers_counterparty_id;",
                "DROP INDEX IF EXISTS idx_exchange_offers_public_profile_id;",
                "DROP INDEX IF EXISTS idx_exchange_offers_status;",
                "DROP INDEX IF EXISTS idx_exchange_offers_visibility;",
                "DROP INDEX IF EXISTS idx_exchange_offers_category;",
                "DROP INDEX IF EXISTS idx_exchange_offers_updated_at;",
                "DROP INDEX IF EXISTS idx_exchange_offers_profile_status_updated_at;",

                "DROP INDEX IF EXISTS idx_exchange_publication_state_status;",
                "DROP INDEX IF EXISTS idx_exchange_publication_state_last_success_at;",
                "DROP INDEX IF EXISTS idx_exchange_publication_state_is_dirty;",
                "DROP INDEX IF EXISTS idx_exchange_publication_state_status_dirty;",
                "DROP INDEX IF EXISTS idx_exchange_publication_state_last_local_mutation_at;",

                "DROP TABLE IF EXISTS exchange_offers;",
                "DROP TABLE IF EXISTS exchange_publication_state;",

                """
                CREATE TABLE IF NOT EXISTS exchange_publication_state (
                    public_profile_id TEXT PRIMARY KEY NOT NULL,
                    status TEXT NOT NULL,
                    is_dirty INTEGER NOT NULL DEFAULT 0,
                    published_at TEXT,
                    last_attempt_at TEXT,
                    last_success_at TEXT,
                    last_local_mutation_at TEXT,
                    last_failure_summary TEXT,
                    last_remote_profile_id TEXT,
                    last_remote_offer_ids_json BLOB NOT NULL,
                    last_published_fingerprint TEXT,
                    metadata_json BLOB NOT NULL,
                    json_snapshot BLOB NOT NULL,
                    FOREIGN KEY(public_profile_id) REFERENCES exchange_public_profiles(id) ON DELETE CASCADE
                );
                """,

                """
                CREATE TABLE IF NOT EXISTS exchange_offers (
                    id TEXT PRIMARY KEY NOT NULL,
                    node_id TEXT NOT NULL,
                    public_profile_id TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    revision INTEGER NOT NULL DEFAULT 1,
                    title TEXT NOT NULL,
                    summary TEXT,
                    category TEXT,
                    status TEXT NOT NULL,
                    visibility TEXT NOT NULL,
                    tags_json BLOB NOT NULL,
                    region_tags_json BLOB NOT NULL,
                    semantic_json BLOB NOT NULL,
                    fulfillment_json BLOB NOT NULL,
                    metadata_json BLOB NOT NULL,
                    json_snapshot BLOB NOT NULL,
                    FOREIGN KEY(public_profile_id) REFERENCES exchange_public_profiles(id) ON DELETE CASCADE
                );
                """,

                "CREATE INDEX IF NOT EXISTS idx_exchange_publication_state_status ON exchange_publication_state(status);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_publication_state_last_success_at ON exchange_publication_state(last_success_at DESC);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_publication_state_is_dirty ON exchange_publication_state(is_dirty);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_publication_state_status_dirty ON exchange_publication_state(status, is_dirty);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_publication_state_last_local_mutation_at ON exchange_publication_state(last_local_mutation_at DESC);",

                "CREATE INDEX IF NOT EXISTS idx_exchange_offers_node_id ON exchange_offers(node_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_offers_public_profile_id ON exchange_offers(public_profile_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_offers_status ON exchange_offers(status);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_offers_visibility ON exchange_offers(visibility);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_offers_category ON exchange_offers(category);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_offers_updated_at ON exchange_offers(updated_at DESC);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_offers_profile_status_updated_at ON exchange_offers(public_profile_id, status, updated_at DESC);"
            ]
        ),

        Migration(
            version: 9,
            statements: [
                // ---------------------------------------------------------------------
                // Offer-aware match persistence upgrade.
                // Pre-launch safe reset of match table shape to align with current model.
                // ---------------------------------------------------------------------

                "DROP INDEX IF EXISTS idx_exchange_match_reasons_match_id;",
                "DROP INDEX IF EXISTS idx_exchange_match_cautions_match_id;",
                "DROP INDEX IF EXISTS idx_exchange_matches_thread_id_created_at;",
                "DROP INDEX IF EXISTS idx_exchange_matches_counterparty_id;",
                "DROP INDEX IF EXISTS idx_exchange_matches_status;",
                "DROP INDEX IF EXISTS idx_exchange_matches_strength_score;",
                "DROP INDEX IF EXISTS idx_exchange_matches_public_profile_id;",
                "DROP INDEX IF EXISTS idx_exchange_matches_offer_id;",
                "DROP INDEX IF EXISTS idx_exchange_matches_scope;",

                "DROP TABLE IF EXISTS exchange_match_reasons;",
                "DROP TABLE IF EXISTS exchange_match_cautions;",
                "DROP TABLE IF EXISTS exchange_matches;",

                """
                CREATE TABLE IF NOT EXISTS exchange_matches (
                    id TEXT PRIMARY KEY NOT NULL,
                    thread_id TEXT NOT NULL,
                    counterparty_id TEXT NOT NULL,
                    scope TEXT NOT NULL,
                    public_profile_id TEXT,
                    offer_id TEXT,
                    matched_offer_ids_json BLOB NOT NULL,
                    created_at TEXT NOT NULL,
                    status TEXT NOT NULL,
                    strength TEXT NOT NULL,
                    score REAL NOT NULL,
                    recommendation TEXT,
                    fit_json BLOB NOT NULL,
                    metadata_json BLOB NOT NULL,
                    json_snapshot BLOB NOT NULL,
                    FOREIGN KEY(thread_id) REFERENCES exchange_threads(id) ON DELETE CASCADE,
                    FOREIGN KEY(counterparty_id) REFERENCES exchange_counterparties(id) ON DELETE CASCADE,
                    FOREIGN KEY(public_profile_id) REFERENCES exchange_public_profiles(id) ON DELETE SET NULL,
                    FOREIGN KEY(offer_id) REFERENCES exchange_offers(id) ON DELETE SET NULL
                );
                """,

                """
                CREATE TABLE IF NOT EXISTS exchange_match_reasons (
                    id TEXT PRIMARY KEY NOT NULL,
                    match_id TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    summary TEXT NOT NULL,
                    FOREIGN KEY(match_id) REFERENCES exchange_matches(id) ON DELETE CASCADE
                );
                """,

                """
                CREATE TABLE IF NOT EXISTS exchange_match_cautions (
                    id TEXT PRIMARY KEY NOT NULL,
                    match_id TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    summary TEXT NOT NULL,
                    FOREIGN KEY(match_id) REFERENCES exchange_matches(id) ON DELETE CASCADE
                );
                """,

                "CREATE INDEX IF NOT EXISTS idx_exchange_matches_thread_id_created_at ON exchange_matches(thread_id, created_at DESC);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_matches_counterparty_id ON exchange_matches(counterparty_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_matches_public_profile_id ON exchange_matches(public_profile_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_matches_offer_id ON exchange_matches(offer_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_matches_scope ON exchange_matches(scope);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_matches_status ON exchange_matches(status);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_matches_strength_score ON exchange_matches(strength, score DESC);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_match_reasons_match_id ON exchange_match_reasons(match_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_match_cautions_match_id ON exchange_match_cautions(match_id);"
            ]
        ),

        Migration(
            version: 10,
            statements: [
                // ---------------------------------------------------------------------
                // Retrieval document + embedding persistence.
                //
                // This aligns the local client schema with the current federation model:
                //
                // Seller push:
                // - seller surface = public profile + offers + posture
                // - retrieval documents = flattened searchable projections
                // - embeddings = vectors attached to retrieval documents
                //
                // Buyer pull:
                // - query text + query embedding
                // - search returns hydrated profile / offer matches
                //
                // Pre-launch note:
                // This is additive and safe. If local test data becomes messy, the app DB
                // can still be reset during private development.
                // ---------------------------------------------------------------------

                """
                CREATE TABLE IF NOT EXISTS exchange_retrieval_documents (
                    id TEXT PRIMARY KEY NOT NULL,

                    owner_node_id TEXT NOT NULL,
                    counterparty_id TEXT,
                    public_profile_id TEXT,
                    offer_id TEXT,

                    source_kind TEXT NOT NULL,
                    surface_type TEXT NOT NULL,

                    title TEXT,
                    summary TEXT,
                    category TEXT,

                    tags_json BLOB NOT NULL,
                    region_tags_json BLOB NOT NULL,
                    semantic_text TEXT,
                    document_text TEXT,

                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    published_at TEXT,

                    metadata_json BLOB NOT NULL,
                    json_snapshot BLOB NOT NULL,

                    FOREIGN KEY(counterparty_id) REFERENCES exchange_counterparties(id) ON DELETE SET NULL,
                    FOREIGN KEY(public_profile_id) REFERENCES exchange_public_profiles(id) ON DELETE CASCADE,
                    FOREIGN KEY(offer_id) REFERENCES exchange_offers(id) ON DELETE CASCADE
                );
                """,

                """
                CREATE TABLE IF NOT EXISTS exchange_retrieval_embeddings (
                    document_id TEXT NOT NULL,
                    model_id TEXT NOT NULL,

                    dimension INTEGER NOT NULL,
                    embedding_json BLOB NOT NULL,

                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,

                    PRIMARY KEY(document_id, model_id),
                    FOREIGN KEY(document_id) REFERENCES exchange_retrieval_documents(id) ON DELETE CASCADE
                );
                """,

                "CREATE INDEX IF NOT EXISTS idx_exchange_retrieval_documents_owner_node_id ON exchange_retrieval_documents(owner_node_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_retrieval_documents_counterparty_id ON exchange_retrieval_documents(counterparty_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_retrieval_documents_public_profile_id ON exchange_retrieval_documents(public_profile_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_retrieval_documents_offer_id ON exchange_retrieval_documents(offer_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_retrieval_documents_source_kind ON exchange_retrieval_documents(source_kind);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_retrieval_documents_surface_type ON exchange_retrieval_documents(surface_type);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_retrieval_documents_updated_at ON exchange_retrieval_documents(updated_at DESC);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_retrieval_documents_published_at ON exchange_retrieval_documents(published_at DESC);",

                "CREATE INDEX IF NOT EXISTS idx_exchange_retrieval_embeddings_document_id ON exchange_retrieval_embeddings(document_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_retrieval_embeddings_model_id ON exchange_retrieval_embeddings(model_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_retrieval_embeddings_dimension ON exchange_retrieval_embeddings(dimension);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_retrieval_embeddings_updated_at ON exchange_retrieval_embeddings(updated_at DESC);",

                "ALTER TABLE exchange_publication_state ADD COLUMN last_retrieval_published_at TEXT;",
                "ALTER TABLE exchange_publication_state ADD COLUMN last_retrieval_document_count INTEGER NOT NULL DEFAULT 0;",
                "ALTER TABLE exchange_publication_state ADD COLUMN last_retrieval_embedded_count INTEGER NOT NULL DEFAULT 0;",
                "ALTER TABLE exchange_publication_state ADD COLUMN last_retrieval_fingerprint TEXT;",
                "ALTER TABLE exchange_publication_state ADD COLUMN last_embedding_model_id TEXT;",
                "ALTER TABLE exchange_publication_state ADD COLUMN last_embedding_dimension INTEGER NOT NULL DEFAULT 0;",

                "CREATE INDEX IF NOT EXISTS idx_exchange_publication_state_last_retrieval_published_at ON exchange_publication_state(last_retrieval_published_at DESC);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_publication_state_last_retrieval_fingerprint ON exchange_publication_state(last_retrieval_fingerprint);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_publication_state_last_embedding_model_id ON exchange_publication_state(last_embedding_model_id);"
            ]
        ),

        Migration(
            version: 11,
            statements: [
                """
                CREATE TABLE IF NOT EXISTS exchange_secretary_notifications (
                    id TEXT PRIMARY KEY NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    dedupe_key TEXT NOT NULL UNIQUE,
                    is_read INTEGER NOT NULL DEFAULT 0,
                    priority TEXT NOT NULL DEFAULT 'normal',
                    title TEXT NOT NULL,
                    body TEXT NOT NULL,
                    thread_id TEXT,
                    approval_id TEXT,
                    failure_id TEXT,
                    turn_id TEXT,
                    trusted_node_id TEXT,
                    metadata_json BLOB NOT NULL,
                    json_snapshot BLOB NOT NULL,
                    FOREIGN KEY(thread_id) REFERENCES exchange_threads(id) ON DELETE SET NULL,
                    FOREIGN KEY(approval_id) REFERENCES exchange_approvals(id) ON DELETE SET NULL,
                    FOREIGN KEY(failure_id) REFERENCES exchange_failures(id) ON DELETE SET NULL,
                    FOREIGN KEY(turn_id) REFERENCES exchange_turns(id) ON DELETE SET NULL
                );
                """,

                "CREATE INDEX IF NOT EXISTS idx_exchange_secretary_notifications_thread_id ON exchange_secretary_notifications(thread_id);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_secretary_notifications_created_at ON exchange_secretary_notifications(created_at DESC);",
                "CREATE INDEX IF NOT EXISTS idx_exchange_secretary_notifications_is_read ON exchange_secretary_notifications(is_read);"
            ]
        ),

        Migration(
            version: 12,
            statements: [
                // v1.6 offer-level public contact details (optional; additive for backward compatibility).
                "ALTER TABLE exchange_offers ADD COLUMN contact_info_json BLOB;"
            ]
        ),

        Migration(
            version: 13,
            statements: [
                """
                CREATE TABLE IF NOT EXISTS outgoing_contact_requests (
                    id TEXT PRIMARY KEY NOT NULL,
                    target_node_id TEXT NOT NULL,
                    target_display_name TEXT,
                    target_profile_id TEXT,
                    envelope_id TEXT NOT NULL,
                    correlation_id TEXT NOT NULL,
                    phase TEXT NOT NULL,
                    body TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    sent_at TEXT,
                    last_error TEXT,
                    metadata_json BLOB NOT NULL,
                    json_snapshot BLOB NOT NULL
                );
                """,
                "CREATE INDEX IF NOT EXISTS idx_outgoing_contact_requests_target ON outgoing_contact_requests(target_node_id);",
                "CREATE INDEX IF NOT EXISTS idx_outgoing_contact_requests_phase ON outgoing_contact_requests(phase);"
            ]
        )
    ]

    public struct Migration: Sendable, Hashable {
        public let version: Int
        public let statements: [String]

        public init(version: Int, statements: [String]) {
            self.version = version
            self.statements = statements
        }
    }
}
