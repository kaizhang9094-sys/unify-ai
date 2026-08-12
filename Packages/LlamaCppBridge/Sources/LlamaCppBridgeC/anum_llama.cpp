#include "anum_llama.h"

// llama.cpp public C API
#include <llama/llama.h>

#include <string>
#include <vector>
#include <cstring>
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <mutex>
#include <atomic>
#include <array>

// HARD LOGGING + file access checks
#include <cstdio>
#include <cerrno>
#include <unistd.h>   // access()
#include <sys/stat.h> // stat()
#include <fcntl.h>    // open()
#include <TargetConditionals.h>

// iOS scheduling / QoS
#if defined(__APPLE__)
  #include <pthread.h>
  #include <pthread/qos.h>
#endif

// -----------------------------
// DEBUG-only logging
// -----------------------------
#if defined(DEBUG) || defined(_DEBUG)
  #define ANUM_LOG_ENABLED 1
#else
  #define ANUM_LOG_ENABLED 0
#endif

#if ANUM_LOG_ENABLED
  #define ANUM_EPRINTF(...) do { std::fprintf(stderr, __VA_ARGS__); } while (0)
  #define ANUM_EFLUSH()     do { std::fflush(stderr); } while (0)
#else
  #define ANUM_EPRINTF(...) do { } while (0)
  #define ANUM_EFLUSH()     do { } while (0)
#endif

static inline void logf(const char* msg) {
    ANUM_EPRINTF("%s\n", msg);
    ANUM_EFLUSH();
}

static inline void log_path(const char* prefix, const char* path) {
    ANUM_EPRINTF("%s%s\n", prefix, path ? path : "(null)");
    ANUM_EFLUSH();
}

static inline void log_errno(const char* prefix) {
    ANUM_EPRINTF("%s errno=%d (%s)\n", prefix, errno, std::strerror(errno));
    ANUM_EFLUSH();
}

static inline int32_t clamp_i32(int32_t v, int32_t lo, int32_t hi) {
    return std::max(lo, std::min(hi, v));
}

static inline int32_t anum_clamp_seq_id(int32_t seq_id) {
    if (seq_id < 0) return 0;
    if (seq_id > 3) return 3;
    return seq_id;
}

static inline void anum_set_qos_for_seq(int32_t seq_id) {
#if defined(__APPLE__)
    if (seq_id == 0) {
        pthread_set_qos_class_self_np(QOS_CLASS_USER_INITIATED, 0);
    } else {
        pthread_set_qos_class_self_np(QOS_CLASS_UTILITY, 0);
    }
#else
    (void)seq_id;
#endif
}

static inline void anum_log_qos(const char* tag) {
#if ANUM_LOG_ENABLED && defined(__APPLE__)
    qos_class_t qc = QOS_CLASS_DEFAULT;
    int rel = 0;
    pthread_get_qos_class_np(pthread_self(), &qc, &rel);
    ANUM_EPRINTF("[anum_llama] qos %s class=%d rel=%d\n", tag ? tag : "(null)", (int)qc, rel);
    ANUM_EFLUSH();
#else
    (void)tag;
#endif
}

static const llama_vocab* get_vocab(llama_model* model) {
    return llama_model_get_vocab(model);
}

static inline bool anum_ends_with(const std::string& s, const std::string& suffix) {
    return s.size() >= suffix.size() &&
           s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
}

static inline bool anum_contains_any_chat_marker(const std::string& s) {
    return s.find("<|im_start|>") != std::string::npos ||
           s.find("<|im_end|>") != std::string::npos ||
           s.find("<start_of_turn>") != std::string::npos ||
           s.find("<end_of_turn>") != std::string::npos;
}

static std::string anum_format_raw_scaffold_for_runtime(const std::string& raw) {
    std::string trimmed = raw;
    while (!trimmed.empty() && (trimmed.back() == '\n' || trimmed.back() == '\r')) {
        trimmed.pop_back();
    }

    if (trimmed.empty()) {
        return std::string();
    }

    std::string formatted;
    formatted.reserve(trimmed.size() + 96);
    formatted += "<start_of_turn>user\n";
    formatted += "[Instruction Context]\n";
    formatted += trimmed;
    formatted += "\n<end_of_turn>\n";
    formatted += "<start_of_turn>model\n";
    formatted += "Understood.\n";
    formatted += "<end_of_turn>\n";
    return formatted;
}

struct anum_prompt_checkpoint_entry {
    std::vector<llama_token> prompt_tokens;
    uint64_t token_fnv1a = 0;
    /// Snapshot taken **before** decoding the final prompt token (KV ends at prefix).
    std::vector<uint8_t> state_blob;
    llama_token final_prompt_token = 0;
    /// `llama_pos` where the final prompt token must be decoded (logits=true) after restore.
    llama_pos next_llama_pos_before_final = 0;
    bool valid = false;
};

struct anum_scaffold_checkpoint_entry {
    std::vector<llama_token> scaffold_tokens;
    uint64_t scaffold_fnv1a = 0;
    llama_pos next_llama_pos_before_tail = 0;
    std::vector<uint8_t> state_blob;
    bool valid = false;
};

struct anum_ctx {
    llama_model* model = nullptr;
    llama_context* ctx = nullptr;
    llama_sampler* sampler = nullptr;

    int32_t n_ctx = 2048;
    int32_t n_threads = 4;
    int32_t n_batch = 256;

    float temperature = 0.8f;
    int32_t top_k = 40;
    float top_p = 0.95f;
    int32_t seed = -1;

    std::atomic<bool> abort_requested{false};
    bool backend_inited = false;

    // Full-replay prefix cache
    bool enable_prefix_cache = true;
    std::array<std::vector<llama_token>, 4> last_prompt_tokens_by_seq;

    // Runtime-owned incremental state
    std::array<llama_pos, 4> cur_pos_by_seq = {0, 0, 0, 0};
    std::array<bool, 4> has_live_state_by_seq = {false, false, false, false};
    std::array<bool, 4> has_live_logits_by_seq = {false, false, false, false};

    // IMPORTANT:
    // After ingest, the valid logits are at the last token index of the final ingest batch.
    // After normal token-by-token generation decode, the valid logits index becomes 0.
    std::array<int32_t, 4> last_logits_index_by_seq = {-1, -1, -1, -1};

    // Optional raw-scaffold dedup for current Swift warm path
    std::array<size_t, 4> last_raw_scaffold_hash_by_seq = {0, 0, 0, 0};

    std::array<anum_prompt_checkpoint_entry, 4> seq_prompt_checkpoint;
    bool pending_checkpoint_regenerate = false;

    std::array<anum_scaffold_checkpoint_entry, 4> seq_scaffold_checkpoint;
    bool pending_scaffold_checkpoint_replay = false;
};

// Thread-safety and backend refcounting
static std::mutex g_generate_mutex;
static std::mutex g_backend_mutex;
static std::atomic<int> g_backend_refcount{0};

static void anum_clear_seq_runtime_state(anum_ctx* a, int32_t seq_id) {
    seq_id = anum_clamp_seq_id(seq_id);
    a->last_prompt_tokens_by_seq[seq_id].clear();
    a->cur_pos_by_seq[seq_id] = 0;
    a->has_live_state_by_seq[seq_id] = false;
    a->has_live_logits_by_seq[seq_id] = false;
    a->last_logits_index_by_seq[seq_id] = -1;
    a->last_raw_scaffold_hash_by_seq[seq_id] = 0;
}

static void anum_clear_all_runtime_state(anum_ctx* a) {
    for (int i = 0; i < 4; ++i) {
        anum_clear_seq_runtime_state(a, i);
    }
}

static bool anum_init_context_from_model(anum_ctx* a) {
    if (!a || !a->model) return false;
    if (a->ctx) return true;

    llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx = a->n_ctx;
    cparams.n_batch = a->n_batch;
    cparams.n_threads = a->n_threads;
    cparams.n_threads_batch = a->n_threads;

    a->ctx = llama_init_from_model(a->model, cparams);
    if (!a->ctx) {
        logf("[anum_llama] llama_init_from_model() FAILED");
        return false;
    }

    anum_clear_all_runtime_state(a);
    logf("[anum_llama] llama_init_from_model() OK");
    return true;
}

static bool tokenize_prompt(llama_model* model, const std::string& prompt, std::vector<llama_token>& out) {
    const llama_vocab* vocab = get_vocab(model);
    int32_t n_max = (int32_t)prompt.size() + 8;
    out.resize(n_max);

    int32_t n = llama_tokenize(
        vocab,
        prompt.c_str(),
        (int32_t)prompt.size(),
        out.data(),
        (int32_t)out.size(),
        true,
        true
    );

    if (n < 0) return false;
    out.resize(n);
    return true;
}

static size_t common_prefix_len(const std::vector<llama_token>& a, const std::vector<llama_token>& b) {
    const size_t n = std::min(a.size(), b.size());
    size_t i = 0;
    for (; i < n; ++i) {
        if (a[i] != b[i]) break;
    }
    return i;
}

static uint64_t anum_fnv1a64_tokens(const std::vector<llama_token>& tokens) {
    uint64_t h = 14695981039346656037ULL;
    for (llama_token t : tokens) {
        h ^= static_cast<uint64_t>(static_cast<uint32_t>(t));
        h *= 1099511628211ULL;
    }
    return h;
}

static void anum_invalidate_prompt_checkpoints(anum_ctx* a) {
    if (!a) return;
    for (int i = 0; i < 4; ++i) {
        a->seq_prompt_checkpoint[(size_t)i].prompt_tokens.clear();
        a->seq_prompt_checkpoint[(size_t)i].state_blob.clear();
        a->seq_prompt_checkpoint[(size_t)i].valid = false;
        a->seq_prompt_checkpoint[(size_t)i].token_fnv1a = 0;
        a->seq_prompt_checkpoint[(size_t)i].final_prompt_token = 0;
        a->seq_prompt_checkpoint[(size_t)i].next_llama_pos_before_final = 0;

        a->seq_scaffold_checkpoint[(size_t)i].scaffold_tokens.clear();
        a->seq_scaffold_checkpoint[(size_t)i].state_blob.clear();
        a->seq_scaffold_checkpoint[(size_t)i].valid = false;
        a->seq_scaffold_checkpoint[(size_t)i].scaffold_fnv1a = 0;
        a->seq_scaffold_checkpoint[(size_t)i].next_llama_pos_before_tail = 0;
    }
    a->pending_checkpoint_regenerate = false;
    a->pending_scaffold_checkpoint_replay = false;
}

static bool anum_prepare_formatted_prompt(
    const char* prompt_utf8,
    std::string& formatted
);

static int32_t anum_generate_from_current_state_locked(
    anum_ctx* a,
    int32_t max_tokens,
    int32_t seq_id,
    anum_token_cb cb,
    void* user_data
);

static int32_t anum_decode_token_span(
    anum_ctx* a,
    const std::vector<llama_token>& tokens,
    size_t start_idx,
    llama_pos start_pos,
    int32_t seq_id,
    bool request_logits_on_last,
    llama_pos& out_cur_pos,
    int32_t& out_last_logits_idx
);

/// Snapshot seq state **after** all prompt tokens except the last are decoded (no logits on prefix tail).
static void anum_prompt_checkpoint_save_prefix_state(
    anum_ctx* a,
    int32_t seq_id,
    const std::vector<llama_token>& full_prompt_tokens,
    llama_token final_prompt_token,
    llama_pos next_llama_pos_before_final
) {
    seq_id = anum_clamp_seq_id(seq_id);
    auto& cp = a->seq_prompt_checkpoint[(size_t)seq_id];

    if (!a->ctx) {
        ANUM_EPRINTF("[PromptCheckpoint] saved seq=%d FAILED reason=no_context\n", (int)seq_id);
        ANUM_EFLUSH();
        cp.valid = false;
        return;
    }

    size_t sz = llama_state_seq_get_size(a->ctx, seq_id);
    if (sz == 0) {
        ANUM_EPRINTF("[PromptCheckpoint] saved seq=%d FAILED reason=stateSize0\n", (int)seq_id);
        ANUM_EFLUSH();
        cp.valid = false;
        return;
    }

    cp.state_blob.resize(sz);
    size_t got = llama_state_seq_get_data(a->ctx, cp.state_blob.data(), sz, seq_id);
    if (got == 0 || got != sz) {
        cp.state_blob.clear();
        cp.valid = false;
        ANUM_EPRINTF(
            "[PromptCheckpoint] saved seq=%d FAILED reason=get_data got=%zu need=%zu\n",
            (int)seq_id,
            (size_t)got,
            sz
        );
        ANUM_EFLUSH();
        return;
    }

    cp.prompt_tokens = full_prompt_tokens;
    cp.token_fnv1a = anum_fnv1a64_tokens(full_prompt_tokens);
    cp.final_prompt_token = final_prompt_token;
    cp.next_llama_pos_before_final = next_llama_pos_before_final;
    cp.valid = true;

    ANUM_EPRINTF(
        "[PromptCheckpoint] saved seq=%d promptTokens=%zu nextBeforeFinal=%d finalTok=%d stateBytes=%zu\n",
        (int)seq_id,
        cp.prompt_tokens.size(),
        (int)cp.next_llama_pos_before_final,
        (int)cp.final_prompt_token,
        cp.state_blob.size()
    );
    ANUM_EFLUSH();
}

static void anum_scaffold_checkpoint_save_from_current(
    anum_ctx* a,
    int32_t seq_id,
    const std::vector<llama_token>& scaffold_tokens,
    llama_pos next_llama_pos_before_tail
) {
    seq_id = anum_clamp_seq_id(seq_id);
    auto& sp = a->seq_scaffold_checkpoint[(size_t)seq_id];

    if (!a->ctx) {
        ANUM_EPRINTF("[ScaffoldCheckpoint] saved seq=%d FAILED reason=no_context\n", (int)seq_id);
        ANUM_EFLUSH();
        sp.valid = false;
        return;
    }

    size_t sz = llama_state_seq_get_size(a->ctx, seq_id);
    if (sz == 0) {
        ANUM_EPRINTF("[ScaffoldCheckpoint] saved seq=%d FAILED reason=stateSize0\n", (int)seq_id);
        ANUM_EFLUSH();
        sp.valid = false;
        return;
    }

    sp.state_blob.resize(sz);
    size_t got = llama_state_seq_get_data(a->ctx, sp.state_blob.data(), sz, seq_id);
    if (got == 0 || got != sz) {
        sp.state_blob.clear();
        sp.valid = false;
        ANUM_EPRINTF(
            "[ScaffoldCheckpoint] saved seq=%d FAILED reason=get_data got=%zu need=%zu\n",
            (int)seq_id,
            (size_t)got,
            sz
        );
        ANUM_EFLUSH();
        return;
    }

    sp.scaffold_tokens = scaffold_tokens;
    sp.scaffold_fnv1a = anum_fnv1a64_tokens(scaffold_tokens);
    sp.next_llama_pos_before_tail = next_llama_pos_before_tail;
    sp.valid = true;

    ANUM_EPRINTF(
        "[ScaffoldCheckpoint] saved seq=%d scaffoldTokens=%zu scaffoldEndPos=%d stateBytes=%zu\n",
        (int)seq_id,
        sp.scaffold_tokens.size(),
        (int)sp.next_llama_pos_before_tail,
        sp.state_blob.size()
    );
    ANUM_EFLUSH();
}

static int32_t anum_decode_dynamic_tail_with_prompt_checkpoint_capture(
    anum_ctx* a,
    int32_t seq_id,
    const std::vector<llama_token>& full_prompt_tokens,
    size_t tail_start_idx,
    llama_pos start_pos_for_first_tail_token,
    bool capture_prompt_checkpoint,
    llama_pos& out_cur_pos,
    int32_t& out_last_logits_idx
) {
    const size_t n = full_prompt_tokens.size();
    if (tail_start_idx > n) {
        return -5;
    }

    const size_t tail_len = n - tail_start_idx;
    if (tail_len == 0) {
        return -5;
    }

    if (tail_len == 1) {
        if (capture_prompt_checkpoint) {
            anum_prompt_checkpoint_save_prefix_state(
                a,
                seq_id,
                full_prompt_tokens,
                full_prompt_tokens[n - 1],
                start_pos_for_first_tail_token
            );
        }

        std::vector<llama_token> one(1, full_prompt_tokens[tail_start_idx]);
        return anum_decode_token_span(
            a,
            one,
            0,
            start_pos_for_first_tail_token,
            seq_id,
            /*request_logits_on_last=*/true,
            out_cur_pos,
            out_last_logits_idx
        );
    }

    std::vector<llama_token> tail_prefix(
        full_prompt_tokens.begin() + (ptrdiff_t)tail_start_idx,
        full_prompt_tokens.end() - 1
    );

    llama_pos out_mid = start_pos_for_first_tail_token;
    int32_t junk_logits = -1;
    const int32_t rc_mid = anum_decode_token_span(
        a,
        tail_prefix,
        0,
        start_pos_for_first_tail_token,
        seq_id,
        /*request_logits_on_last=*/false,
        out_mid,
        junk_logits
    );

    if (rc_mid != 0) {
        return rc_mid;
    }

    if (capture_prompt_checkpoint) {
        anum_prompt_checkpoint_save_prefix_state(
            a,
            seq_id,
            full_prompt_tokens,
            full_prompt_tokens[n - 1],
            out_mid
        );
    }

    std::vector<llama_token> final_one(1, full_prompt_tokens[n - 1]);
    return anum_decode_token_span(
        a,
        final_one,
        0,
        out_mid,
        seq_id,
        /*request_logits_on_last=*/true,
        out_cur_pos,
        out_last_logits_idx
    );
}

static int32_t anum_scaffold_checkpoint_replay_locked(
    anum_ctx* a,
    const char* prompt_utf8,
    const char* scaffold_utf8,
    uint32_t flags,
    int32_t max_tokens,
    int32_t seq_id,
    anum_token_cb cb,
    void* user_data
) {
    seq_id = anum_clamp_seq_id(seq_id);
    auto& scp = a->seq_scaffold_checkpoint[(size_t)seq_id];

    if (!scaffold_utf8 || scaffold_utf8[0] == '\0') {
        ANUM_EPRINTF("[ScaffoldCheckpoint] restoreMiss seq=%d reason=no_scaffold_utf8\n", (int)seq_id);
        ANUM_EFLUSH();
        return -5;
    }

    std::string formatted;
    if (!anum_prepare_formatted_prompt(prompt_utf8, formatted)) {
        struct DoneOnce {
            anum_token_cb cb;
            void* ud;
            bool done;
            DoneOnce(anum_token_cb cb_, void* ud_) : cb(cb_), ud(ud_), done(false) {}
            void finish() { if (!done) { done = true; if (cb) cb("", ud); } }
            ~DoneOnce() { if (!done && cb) cb("", ud); }
        } done(cb, user_data);
        done.finish();
        return -2;
    }

    const std::string scaff_str(scaffold_utf8);
    if (formatted.size() < scaff_str.size() || formatted.compare(0, scaff_str.size(), scaff_str) != 0) {
        ANUM_EPRINTF("[ScaffoldCheckpoint] restoreMiss seq=%d reason=scaffold_prefix_mismatch\n", (int)seq_id);
        ANUM_EFLUSH();
        return -5;
    }

    std::vector<llama_token> prompt_tokens;
    if (!tokenize_prompt(a->model, formatted, prompt_tokens)) {
        struct DoneOnce {
            anum_token_cb cb;
            void* ud;
            bool done;
            DoneOnce(anum_token_cb cb_, void* ud_) : cb(cb_), ud(ud_), done(false) {}
            void finish() { if (!done) { done = true; if (cb) cb("", ud); } }
            ~DoneOnce() { if (!done && cb) cb("", ud); }
        } done(cb, user_data);
        done.finish();
        return -3;
    }

    std::vector<llama_token> scaffold_tokens;
    if (!tokenize_prompt(a->model, scaff_str, scaffold_tokens)) {
        struct DoneOnce {
            anum_token_cb cb;
            void* ud;
            bool done;
            DoneOnce(anum_token_cb cb_, void* ud_) : cb(cb_), ud(ud_), done(false) {}
            void finish() { if (!done) { done = true; if (cb) cb("", ud); } }
            ~DoneOnce() { if (!done && cb) cb("", ud); }
        } done(cb, user_data);
        done.finish();
        return -3;
    }

    if (scaffold_tokens.size() > prompt_tokens.size()) {
        ANUM_EPRINTF("[ScaffoldCheckpoint] restoreMiss seq=%d reason=scaffold_longer_than_prompt\n", (int)seq_id);
        ANUM_EFLUSH();
        return -5;
    }

    for (size_t i = 0; i < scaffold_tokens.size(); ++i) {
        if (prompt_tokens[i] != scaffold_tokens[i]) {
            ANUM_EPRINTF("[ScaffoldCheckpoint] restoreMiss seq=%d reason=token_mismatch_at_%zu\n", (int)seq_id, i);
            ANUM_EFLUSH();
            return -5;
        }
    }

    const uint64_t fnv_sc = anum_fnv1a64_tokens(scaffold_tokens);

    if (!scp.valid || scp.state_blob.empty()) {
        ANUM_EPRINTF("[ScaffoldCheckpoint] restoreMiss seq=%d reason=no_checkpoint\n", (int)seq_id);
        ANUM_EFLUSH();
        return -5;
    }

    if (scp.scaffold_tokens.size() != scaffold_tokens.size() || scp.scaffold_tokens != scaffold_tokens) {
        ANUM_EPRINTF("[ScaffoldCheckpoint] restoreMiss seq=%d reason=scaffold_tokens_changed\n", (int)seq_id);
        ANUM_EFLUSH();
        return -5;
    }

    if (scp.scaffold_fnv1a != fnv_sc) {
        ANUM_EPRINTF("[ScaffoldCheckpoint] restoreMiss seq=%d reason=hash_mismatch\n", (int)seq_id);
        ANUM_EFLUSH();
        return -5;
    }

    llama_memory_t mem = llama_get_memory(a->ctx);
    if (mem) {
        llama_memory_seq_rm(mem, seq_id, 0, -1);
    }
    llama_perf_context_reset(a->ctx);

    size_t set_rc = llama_state_seq_set_data(
        a->ctx,
        scp.state_blob.data(),
        scp.state_blob.size(),
        seq_id
    );

    if (set_rc == 0) {
        ANUM_EPRINTF("[ScaffoldCheckpoint] restoreFailed seq=%d rc=0 (trying ext)\n", (int)seq_id);
        ANUM_EFLUSH();

        set_rc = llama_state_seq_set_data_ext(
            a->ctx,
            scp.state_blob.data(),
            scp.state_blob.size(),
            seq_id,
            0
        );

        if (set_rc == 0) {
            ANUM_EPRINTF("[ScaffoldCheckpoint] restoreFailed seq=%d rc=0\n", (int)seq_id);
            ANUM_EFLUSH();
            return -5;
        }
    }

    const size_t K = scaffold_tokens.size();
    const size_t tail_toks = prompt_tokens.size() - K;

    ANUM_EPRINTF(
        "[ScaffoldCheckpoint] restoreHit seq=%d scaffoldTokens=%zu tailTokens=%zu\n",
        (int)seq_id,
        K,
        tail_toks
    );
    ANUM_EFLUSH();

    llama_pos cur_pos = scp.next_llama_pos_before_tail;
    int32_t last_logits_idx = -1;
    const bool capture_prompt = (flags & ANUM_GENERATE_EX_FLAG_CAPTURE_PROMPT_CHECKPOINT) != 0;

    const int32_t rc_tail = anum_decode_dynamic_tail_with_prompt_checkpoint_capture(
        a,
        seq_id,
        prompt_tokens,
        K,
        cur_pos,
        capture_prompt,
        cur_pos,
        last_logits_idx
    );

    ANUM_EPRINTF(
        "[ScaffoldCheckpoint] tailDecode rc=%d tailTokens=%zu\n",
        (int)rc_tail,
        tail_toks
    );
    ANUM_EFLUSH();

    if (rc_tail != 0) {
        return rc_tail;
    }

    if (last_logits_idx < 0) {
        ANUM_EPRINTF("[ScaffoldCheckpoint] restoreFailed seq=%d reason=no_logits_after_tail\n", (int)seq_id);
        ANUM_EFLUSH();
        return -8;
    }

    a->last_prompt_tokens_by_seq[seq_id] = prompt_tokens;
    a->cur_pos_by_seq[seq_id] = cur_pos;
    a->has_live_state_by_seq[seq_id] = true;
    a->has_live_logits_by_seq[seq_id] = true;
    a->last_logits_index_by_seq[seq_id] = last_logits_idx;
    a->last_raw_scaffold_hash_by_seq[seq_id] = 0;

    max_tokens = clamp_i32(max_tokens, 0, 2048);

    if (max_tokens == 0) {
        if (cb) {
            cb("", user_data);
        }
        return 0;
    }

    return anum_generate_from_current_state_locked(a, max_tokens, seq_id, cb, user_data);
}

static int32_t anum_checkpoint_regenerate_locked(
    anum_ctx* a,
    const std::vector<llama_token>& prompt_tokens,
    uint64_t token_fnv1a,
    int32_t max_tokens,
    int32_t seq_id,
    anum_token_cb cb,
    void* user_data
) {
    seq_id = anum_clamp_seq_id(seq_id);
    auto& cp = a->seq_prompt_checkpoint[(size_t)seq_id];

    if (!cp.valid || cp.state_blob.empty()) {
        ANUM_EPRINTF("[PromptCheckpoint] restoreMiss seq=%d reason=no_checkpoint\n", (int)seq_id);
        ANUM_EFLUSH();
        return -5;
    }

    if (cp.prompt_tokens.size() != prompt_tokens.size() || cp.prompt_tokens != prompt_tokens) {
        ANUM_EPRINTF("[PromptCheckpoint] restoreMiss seq=%d reason=token_mismatch\n", (int)seq_id);
        ANUM_EFLUSH();
        return -5;
    }

    if (cp.token_fnv1a != token_fnv1a) {
        ANUM_EPRINTF("[PromptCheckpoint] restoreMiss seq=%d reason=hash_mismatch\n", (int)seq_id);
        ANUM_EFLUSH();
        return -5;
    }

    if (!a->ctx) {
        ANUM_EPRINTF("[PromptCheckpoint] restoreMiss seq=%d reason=no_context\n", (int)seq_id);
        ANUM_EFLUSH();
        return -5;
    }

    llama_memory_t mem = llama_get_memory(a->ctx);
    if (mem) {
        llama_memory_seq_rm(mem, seq_id, 0, -1);
    }
    llama_perf_context_reset(a->ctx);

    size_t set_rc = llama_state_seq_set_data(
        a->ctx,
        cp.state_blob.data(),
        cp.state_blob.size(),
        seq_id
    );

    if (set_rc == 0) {
        ANUM_EPRINTF("[PromptCheckpoint] restoreFailed seq=%d rc=0 (trying ext)\n", (int)seq_id);
        ANUM_EFLUSH();

        set_rc = llama_state_seq_set_data_ext(
            a->ctx,
            cp.state_blob.data(),
            cp.state_blob.size(),
            seq_id,
            0
        );

        if (set_rc == 0) {
            ANUM_EPRINTF("[PromptCheckpoint] restoreFailed seq=%d rc=0\n", (int)seq_id);
            ANUM_EFLUSH();
            return -5;
        }
    }

    // Restore leaves KV aligned with prefix-only snapshot; logits are not valid until we re-decode the
    // final prompt token with logits=true (matches fullReplay ingest tail).
    {
        std::vector<llama_token> final_one(1, cp.final_prompt_token);
        llama_pos out_cur = cp.next_llama_pos_before_final;
        int32_t refresh_logits_idx = -1;
        const int32_t rc_final = anum_decode_token_span(
            a,
            final_one,
            0,
            cp.next_llama_pos_before_final,
            seq_id,
            /*request_logits_on_last=*/true,
            out_cur,
            refresh_logits_idx
        );
        if (rc_final != 0) {
            ANUM_EPRINTF(
                "[PromptCheckpoint] restoreFailed seq=%d reason=final_prompt_decode rc=%d\n",
                (int)seq_id,
                (int)rc_final
            );
            ANUM_EFLUSH();
            return -5;
        }

        if (refresh_logits_idx < 0) {
            ANUM_EPRINTF(
                "[PromptCheckpoint] restoreFailed seq=%d reason=no_logits_after_final_decode logitsIdx=%d\n",
                (int)seq_id,
                (int)refresh_logits_idx
            );
            ANUM_EFLUSH();
            return -8;
        }

        a->last_prompt_tokens_by_seq[seq_id] = cp.prompt_tokens;
        a->cur_pos_by_seq[seq_id] = out_cur;
        a->has_live_state_by_seq[seq_id] = true;
        a->has_live_logits_by_seq[seq_id] = true;
        a->last_logits_index_by_seq[seq_id] = refresh_logits_idx;
        a->last_raw_scaffold_hash_by_seq[seq_id] = 0;
    }

    ANUM_EPRINTF(
        "[PromptCheckpoint] restoreHit seq=%d promptTokens=%zu nextBeforeFinal=%d finalTok=%d lastLogitsIdx=%d\n",
        (int)seq_id,
        cp.prompt_tokens.size(),
        (int)cp.next_llama_pos_before_final,
        (int)cp.final_prompt_token,
        (int)a->last_logits_index_by_seq[seq_id]
    );
    ANUM_EFLUSH();

    if (max_tokens == 0) {
        if (cb) {
            cb("", user_data);
        }
        return 0;
    }

    return anum_generate_from_current_state_locked(a, max_tokens, seq_id, cb, user_data);
}

static void batch_add(llama_batch& batch, llama_token tok, llama_pos pos, bool logits, int32_t seq_id) {
    batch.token[batch.n_tokens] = tok;
    batch.pos[batch.n_tokens] = pos;
    batch.seq_id[batch.n_tokens][0] = seq_id;
    batch.n_seq_id[batch.n_tokens] = 1;
    batch.logits[batch.n_tokens] = logits ? 1 : 0;
    batch.n_tokens++;
}

static inline std::string anum_rtrim_copy(std::string s) {
    while (!s.empty()) {
        const char c = s.back();
        if (c == '\n' || c == '\r' || c == ' ' || c == '\t') {
            s.pop_back();
        } else {
            break;
        }
    }
    return s;
}

static bool anum_prepare_formatted_prompt(const char* prompt_utf8, std::string& formatted) {
    formatted = prompt_utf8 ? std::string(prompt_utf8) : std::string();
    if (formatted.empty()) {
        return false;
    }

    const std::string trimmed = anum_rtrim_copy(formatted);

    const bool has_chatml =
        formatted.find("<|im_start|>") != std::string::npos ||
        formatted.find("<|im_end|>") != std::string::npos;

    const bool has_gemma_turns =
        formatted.find("<start_of_turn>") != std::string::npos ||
        formatted.find("<end_of_turn>") != std::string::npos;

    // Qwen/Qwen3.5 valid generation endings:
    //
    // 1) Plain assistant generation prefix:
    //    <|im_start|>assistant
    //
    // 2) No-thinking template prefix emitted by Swift:
    //    <|im_start|>assistant
    //    <think>
    //
    //    </think>
    //
    // Both are valid. Do NOT auto-append another assistant prefix after the no-think block.
    bool has_chatml_generation_prefix = false;
    if (has_chatml) {
        if (anum_ends_with(trimmed, "<|im_start|>assistant")) {
            has_chatml_generation_prefix = true;
        }

        const std::string qwen_no_think_suffix_1 =
            "<|im_start|>assistant\n<think>\n\n</think>";

        const std::string qwen_no_think_suffix_2 =
            "<|im_start|>assistant\r\n<think>\r\n\r\n</think>";

        if (anum_ends_with(trimmed, qwen_no_think_suffix_1) ||
            anum_ends_with(trimmed, qwen_no_think_suffix_2)) {
            has_chatml_generation_prefix = true;
        }

        // More tolerant fallback:
        // If the last assistant block contains an already-closed <think> section and no <|im_end|>
        // after that assistant start, treat it as a valid open assistant generation prefix.
        const size_t last_asst = trimmed.rfind("<|im_start|>assistant");
        if (last_asst != std::string::npos) {
            const std::string tail = trimmed.substr(last_asst);
            const bool has_closed_think =
                tail.find("<think>") != std::string::npos &&
                tail.find("</think>") != std::string::npos;

            const bool assistant_block_already_closed =
                tail.find("<|im_end|>") != std::string::npos;

            if (has_closed_think && !assistant_block_already_closed) {
                has_chatml_generation_prefix = true;
            }
        }
    }

    bool has_gemma_model_prefix = false;
    if (has_gemma_turns) {
        has_gemma_model_prefix = anum_ends_with(trimmed, "<start_of_turn>model");
    }

    if (has_chatml) {
        if (!has_chatml_generation_prefix) {
            logf("[anum_llama] WARNING: ChatML prompt missing final assistant prefix -> auto-appending");
            if (!formatted.empty() && formatted.back() != '\n') {
                formatted.push_back('\n');
            }
            formatted.append("<|im_start|>assistant\n");
        }
    } else if (has_gemma_turns) {
        if (!has_gemma_model_prefix) {
            logf("[anum_llama] WARNING: Gemma prompt missing final model prefix -> auto-appending");
            if (!formatted.empty() && formatted.back() != '\n') {
                formatted.push_back('\n');
            }
            formatted.append("<start_of_turn>model\n");
        }
    } else {
        logf("[anum_llama] WARNING: prompt missing recognized chat markers (neither ChatML nor Gemma)");
    }

    return true;
}

static int32_t anum_decode_token_span(
    anum_ctx* a,
    const std::vector<llama_token>& tokens,
    size_t start_idx,
    llama_pos start_pos,
    int32_t seq_id,
    bool request_logits_on_last,
    llama_pos& out_cur_pos,
    int32_t& out_last_logits_idx
) {
    if (!a || !a->ctx) return -7;

    llama_batch batch = llama_batch_init(a->n_batch, 0, 4);
    if (!batch.token || !batch.pos || !batch.logits) {
        llama_batch_free(batch);
        return -4;
    }

    llama_pos cur_pos = start_pos;
    size_t i = start_idx;
    out_last_logits_idx = -1;

    while (i < tokens.size()) {
        if (a->abort_requested.load(std::memory_order_relaxed)) {
            llama_batch_free(batch);
            return -9;
        }

        batch.n_tokens = 0;
        const size_t n_take = std::min((size_t)a->n_batch, tokens.size() - i);

        ANUM_EPRINTF(
            "[anum_llama] ingest chunk i=%zu n_take=%zu cur_pos_start=%d seq=%d\n",
            i, n_take, (int)cur_pos, (int)seq_id
        );
        ANUM_EFLUSH();

        for (size_t j = 0; j < n_take; ++j) {
            const bool request_logits =
                request_logits_on_last && (i + j == tokens.size() - 1);
            batch_add(batch, tokens[i + j], cur_pos, request_logits, seq_id);
            if (request_logits) {
                out_last_logits_idx = (int32_t)batch.n_tokens - 1;
            }
            cur_pos++;
        }
        i += n_take;

        const int rc = llama_decode(a->ctx, batch);
        ANUM_EPRINTF(
            "[anum_llama] ingest decode rc=%d batch_tokens=%d cur_pos_end=%d seq=%d\n",
            rc, (int)batch.n_tokens, (int)cur_pos, (int)seq_id
        );
        ANUM_EFLUSH();

        if (rc != 0) {
            llama_batch_free(batch);
            return -5;
        }
    }

    llama_batch_free(batch);
    out_cur_pos = cur_pos;
    return 0;
}

static int32_t anum_generate_from_current_state_locked(
    anum_ctx* a,
    int32_t max_tokens,
    int32_t seq_id,
    anum_token_cb cb,
    void* user_data
) {
    if (!a || !a->ctx || !a->model || !a->sampler) return -1;
    if (!a->has_live_state_by_seq[seq_id] || !a->has_live_logits_by_seq[seq_id]) {
        logf("[anum_llama] continue failed: no live state/logits for seq");
        return -8;
    }

    max_tokens = clamp_i32(max_tokens, 0, 2048);

    struct DoneOnce {
        anum_token_cb cb;
        void* ud;
        bool done;
        DoneOnce(anum_token_cb cb_, void* ud_) : cb(cb_), ud(ud_), done(false) {}
        void finish() {
            if (!done) {
                done = true;
                if (cb) cb("", ud);
            }
        }
        ~DoneOnce() {
            if (!done && cb) cb("", ud);
        }
    } done(cb, user_data);

    if (max_tokens == 0) {
        done.finish();
        return 0;
    }

    llama_sampler_reset(a->sampler);

    const llama_vocab* vocab = get_vocab(a->model);
    llama_pos cur_pos = a->cur_pos_by_seq[seq_id];

    llama_batch batch = llama_batch_init(a->n_batch, 0, 4);
    if (!batch.token || !batch.pos || !batch.logits) {
        llama_batch_free(batch);
        done.finish();
        return -4;
    }

    int32_t emitted_chunks = 0;
    bool ended_on_eog = false;
    bool ended_on_abort = false;
    bool ended_on_turn_marker = false;

    std::string pending_text;
    const std::string kGemmaEndMarker = "<end_of_turn>";
    const std::string kChatMLEndMarker = "<|im_end|>";
    constexpr size_t kTurnMarkerLookback = 64;

    auto emit_text = [&](const std::string& s) {
        if (!s.empty() && cb) {
            cb(s.c_str(), user_data);
            emitted_chunks++;
        }
    };

    for (int32_t t = 0; t < max_tokens; ++t) {
        if (a->abort_requested.load(std::memory_order_relaxed)) {
            ended_on_abort = true;
            llama_batch_free(batch);
            done.finish();
            a->has_live_logits_by_seq[seq_id] = false;
            a->last_logits_index_by_seq[seq_id] = -1;
            return -9;
        }

        int32_t sample_idx = a->last_logits_index_by_seq[seq_id];
        if (!a->has_live_logits_by_seq[seq_id] || sample_idx < 0) {
            ANUM_EPRINTF(
                "[PromptCheckpoint] invalidLogitsBeforeSample seq=%d sampleIdx=%d\n",
                (int)seq_id,
                (int)sample_idx
            );
            ANUM_EFLUSH();
            llama_batch_free(batch);
            done.finish();
            return -8;
        }

        llama_token tok = llama_sampler_sample(a->sampler, a->ctx, sample_idx);
        llama_sampler_accept(a->sampler, tok);

        if (llama_vocab_is_eog(vocab, tok) || tok == llama_vocab_eos(vocab)) {
            ended_on_eog = true;
            break;
        }

        char buf[4096];
        const int32_t n = llama_token_to_piece(
            vocab,
            tok,
            buf,
            (int32_t)sizeof(buf),
            0,
            false
        );

        if (n > 0) {
            buf[std::min<int32_t>(n, (int32_t)sizeof(buf) - 1)] = '\0';
            pending_text += std::string(buf);

            size_t marker_pos = std::string::npos;
            for (const std::string* marker : {&kGemmaEndMarker, &kChatMLEndMarker}) {
                const size_t pos = pending_text.find(*marker);
                if (pos != std::string::npos && (marker_pos == std::string::npos || pos < marker_pos)) {
                    marker_pos = pos;
                }
            }

            if (marker_pos != std::string::npos) {
                const std::string emit_now = pending_text.substr(0, marker_pos);
                if (!emit_now.empty()) emit_text(emit_now);
                pending_text.clear();
                ended_on_turn_marker = true;
                break;
            }

            if (pending_text.size() > kTurnMarkerLookback) {
                const size_t safe_len = pending_text.size() - kTurnMarkerLookback;
                const std::string emit_now = pending_text.substr(0, safe_len);
                pending_text.erase(0, safe_len);
                if (!emit_now.empty()) emit_text(emit_now);
            }
        }

        batch.n_tokens = 0;
        batch_add(batch, tok, cur_pos, true, seq_id);
        cur_pos++;

        const int rc_gen = llama_decode(a->ctx, batch);
        if (rc_gen != 0) {
            llama_batch_free(batch);
            done.finish();
            a->has_live_logits_by_seq[seq_id] = false;
            a->last_logits_index_by_seq[seq_id] = -1;
            return -6;
        }

        a->cur_pos_by_seq[seq_id] = cur_pos;
        a->has_live_state_by_seq[seq_id] = true;
        a->has_live_logits_by_seq[seq_id] = true;

        // After a single-token generation decode, next valid logits index is 0.
        a->last_logits_index_by_seq[seq_id] = 0;
    }

    if (!pending_text.empty()) {
        size_t marker_pos = std::string::npos;
        for (const std::string* marker : {&kGemmaEndMarker, &kChatMLEndMarker}) {
            const size_t pos = pending_text.find(*marker);
            if (pos != std::string::npos && (marker_pos == std::string::npos || pos < marker_pos)) {
                marker_pos = pos;
            }
        }

        if (marker_pos != std::string::npos) {
            const std::string emit_now = pending_text.substr(0, marker_pos);
            if (!emit_now.empty()) emit_text(emit_now);
        } else {
            emit_text(pending_text);
        }
        pending_text.clear();
    }

    llama_batch_free(batch);
    done.finish();

    if (ended_on_eog || ended_on_turn_marker || ended_on_abort) {
        a->has_live_logits_by_seq[seq_id] = false;
        a->last_logits_index_by_seq[seq_id] = -1;
    }

    ANUM_EPRINTF(
        "[anum_llama] continue EXIT emitted_chunks=%d ended_on_eog=%d ended_on_abort=%d ended_on_turn_marker=%d seq=%d cur_pos=%d last_logits_idx=%d\n",
        (int)emitted_chunks,
        (int)ended_on_eog,
        (int)ended_on_abort,
        (int)ended_on_turn_marker,
        (int)seq_id,
        (int)a->cur_pos_by_seq[seq_id],
        (int)a->last_logits_index_by_seq[seq_id]
    );
    ANUM_EFLUSH();

    return 0;
}

static int32_t anum_ingest_prefix_fragment_locked(
    anum_ctx* a,
    const std::string& fragment,
    int32_t seq_id,
    int32_t max_tokens
) {
    if (!a || !a->ctx) return -7;
    if (fragment.empty()) return 0;

    std::vector<llama_token> tokens;
    if (!tokenize_prompt(a->model, fragment, tokens)) {
        logf("[anum_llama] continue prefix tokenize failed");
        return -3;
    }

    if (tokens.empty()) {
        return 0;
    }

    const int32_t reserve_for_gen = std::min<int32_t>(std::max<int32_t>(max_tokens, 0), 512);
    const int32_t remaining_prompt_budget =
        std::max<int32_t>(0, a->n_ctx - (int32_t)a->cur_pos_by_seq[seq_id] - reserve_for_gen);

    if (remaining_prompt_budget <= 0) {
        ANUM_EPRINTF(
            "[anum_llama] continue prefix skip: no remaining prompt budget seq=%d cur_pos=%d reserve=%d n_ctx=%d\n",
            (int)seq_id,
            (int)a->cur_pos_by_seq[seq_id],
            (int)reserve_for_gen,
            (int)a->n_ctx
        );
        ANUM_EFLUSH();
        return 0;
    }

    if ((int32_t)tokens.size() > remaining_prompt_budget) {
        tokens.resize((size_t)remaining_prompt_budget);
    }

    llama_pos new_pos = a->cur_pos_by_seq[seq_id];
    int32_t last_logits_idx = -1;
    const int32_t rc = anum_decode_token_span(
        a,
        tokens,
        0,
        a->cur_pos_by_seq[seq_id],
        seq_id,
        /*request_logits_on_last=*/true,
        new_pos,
        last_logits_idx
    );
    if (rc != 0) return rc;

    a->cur_pos_by_seq[seq_id] = new_pos;
    a->has_live_state_by_seq[seq_id] = true;
    a->has_live_logits_by_seq[seq_id] = true;
    a->last_logits_index_by_seq[seq_id] = last_logits_idx;
    return 0;
}

anum_llama_t anum_llama_create(const char* model_path, anum_llama_params_t p) {
    logf("[anum_llama] create() ENTER");
    anum_set_qos_for_seq(0);
    anum_log_qos("create_enter");

    if (!model_path || std::strlen(model_path) == 0) {
        logf("[anum_llama] create() invalid model_path (empty)");
        return nullptr;
    }

    log_path("[anum_llama] model_path=", model_path);

    if (access(model_path, R_OK) != 0) {
        logf("[anum_llama] access(R_OK) FAILED");
        log_errno("[anum_llama] access(R_OK)");
        return nullptr;
    }
    logf("[anum_llama] access(R_OK) OK");

    {
        struct stat st;
        if (stat(model_path, &st) != 0) {
            logf("[anum_llama] stat() FAILED");
            log_errno("[anum_llama] stat()");
        } else {
            ANUM_EPRINTF("[anum_llama] model_file_size_bytes=%lld\n", (long long)st.st_size);
            ANUM_EFLUSH();
        }

        int fd = open(model_path, O_RDONLY);
        if (fd < 0) {
            logf("[anum_llama] open() FAILED");
            log_errno("[anum_llama] open()");
        } else {
            unsigned char head[8] = {0};
            ssize_t n = read(fd, head, sizeof(head));
            close(fd);
            if (n > 0) {
                ANUM_EPRINTF(
                    "[anum_llama] model_file_head_bytes=%02X %02X %02X %02X %02X %02X %02X %02X (read=%zd)\n",
                    head[0], head[1], head[2], head[3], head[4], head[5], head[6], head[7], n
                );
                ANUM_EFLUSH();
            }
        }
    }

    auto* a = new anum_ctx();

    a->n_ctx        = (p.n_ctx > 0) ? p.n_ctx : 2048;
    a->n_threads    = (p.n_threads > 0) ? p.n_threads : 4;
    a->n_batch      = (p.n_batch > 0) ? p.n_batch : 256;
    a->temperature  = (p.temperature > 0.0f) ? p.temperature : 0.8f;
    a->top_k        = (p.top_k > 0) ? p.top_k : 40;
    a->top_p        = (p.top_p > 0.0f && p.top_p <= 1.0f) ? p.top_p : 0.95f;
    a->seed         = p.seed;

    {
        std::lock_guard<std::mutex> lock(g_backend_mutex);
        if (g_backend_refcount.fetch_add(1) == 0) {
            logf("[anum_llama] llama_backend_init()");
            llama_backend_init();
            logf("[anum_llama] llama_backend_init() OK");
        }
    }
    a->backend_inited = true;

    llama_model_params mparams = llama_model_default_params();
#if TARGET_OS_SIMULATOR
    mparams.use_mmap = true;
    mparams.use_mlock = false;
    mparams.n_gpu_layers = 0;
#elif TARGET_OS_IPHONE
    mparams.use_mmap = true;
    mparams.use_mlock = false;
#endif

    a->model = llama_model_load_from_file(model_path, mparams);

#if defined(__APPLE__)
    if (!a->model && mparams.use_mmap) {
        logf("[anum_llama] mmap load failed -> retry with use_mmap=false");
        llama_model_params retry = mparams;
        retry.use_mmap = false;
        retry.use_mlock = false;
        a->model = llama_model_load_from_file(model_path, retry);
    }
#endif

    if (!a->model) {
        logf("[anum_llama] llama_model_load_from_file() FAILED");
        anum_llama_destroy((anum_llama_t)a);
        return nullptr;
    }
    logf("[anum_llama] llama_model_load_from_file() OK");

    if (!anum_init_context_from_model(a)) {
        anum_llama_destroy((anum_llama_t)a);
        return nullptr;
    }

    llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    a->sampler = llama_sampler_chain_init(sparams);
    if (!a->sampler) {
        logf("[anum_llama] llama_sampler_chain_init() FAILED");
        anum_llama_destroy((anum_llama_t)a);
        return nullptr;
    }

    llama_sampler_chain_add(
        a->sampler,
        llama_sampler_init_penalties(/*penalty_last_n=*/64, /*repeat=*/1.10f, /*freq=*/0.05f, /*present=*/0.00f)
    );
    llama_sampler_chain_add(a->sampler, llama_sampler_init_top_k(a->top_k));
    llama_sampler_chain_add(a->sampler, llama_sampler_init_top_p(a->top_p, 1));
    llama_sampler_chain_add(a->sampler, llama_sampler_init_temp(a->temperature));
    llama_sampler_chain_add(a->sampler, llama_sampler_init_dist(a->seed));

    logf("[anum_llama] create() SUCCESS");
    return (anum_llama_t)a;
}

void anum_llama_destroy(anum_llama_t ctx) {
    auto* a = (anum_ctx*)ctx;
    if (!a) return;

    if (a->sampler) {
        llama_sampler_free(a->sampler);
        a->sampler = nullptr;
    }
    if (a->ctx) {
        llama_free(a->ctx);
        a->ctx = nullptr;
    }
    if (a->model) {
        llama_model_free(a->model);
        a->model = nullptr;
    }

    if (a->backend_inited) {
        a->backend_inited = false;
        std::lock_guard<std::mutex> lock(g_backend_mutex);
        const int after = g_backend_refcount.fetch_sub(1) - 1;
        if (after == 0) {
            logf("[anum_llama] llama_backend_free() (last ref)");
            llama_backend_free();
        }
    }

    delete a;
}

int32_t anum_llama_abort(anum_llama_t ctx) {
    auto* a = (anum_ctx*)ctx;
    if (!a) return -1;
    a->abort_requested.store(true, std::memory_order_relaxed);
    return 0;
}

int32_t anum_llama_clear_abort(anum_llama_t ctx) {
    auto* a = (anum_ctx*)ctx;
    if (!a) return -1;
    a->abort_requested.store(false, std::memory_order_relaxed);
    return 0;
}

int32_t anum_llama_reset(anum_llama_t ctx, anum_reset_mode_t mode) {
    auto* a = (anum_ctx*)ctx;
    if (!a) return -1;

    std::lock_guard<std::mutex> gen_lock(g_generate_mutex);

    a->abort_requested.store(false, std::memory_order_relaxed);

    if (mode == ANUM_RESET_NONE) {
        return 0;
    }

    if (mode == ANUM_RESET_KV) {
        if (a->ctx) {
            llama_memory_t mem = llama_get_memory(a->ctx);
            if (mem) {
                for (int seq = 0; seq < 4; ++seq) {
                    llama_memory_seq_rm(mem, seq, 0, -1);
                }
            }
            llama_perf_context_reset(a->ctx);
        }
        anum_clear_all_runtime_state(a);
        return 0;
    }

    if (mode == ANUM_RESET_FULL) {
        if (a->ctx) {
            llama_free(a->ctx);
            a->ctx = nullptr;
        }
        anum_clear_all_runtime_state(a);
        anum_invalidate_prompt_checkpoints(a);
        if (!anum_init_context_from_model(a)) {
            return -7;
        }
        return 0;
    }

    if (mode == ANUM_RESET_PROMPT_CHECKPOINT_REGENERATE) {
        a->pending_checkpoint_regenerate = true;
        return 0;
    }

    if (mode == ANUM_RESET_SCAFFOLD_CHECKPOINT_REPLAY) {
        a->pending_scaffold_checkpoint_replay = true;
        return 0;
    }

    return -1;
}

int32_t anum_llama_ingest_ex(
    anum_llama_t ctx,
    const char* prompt_utf8,
    int32_t seq_id
) {
    auto* a = (anum_ctx*)ctx;
    if (!a || !a->model || !a->sampler) return -1;

    seq_id = anum_clamp_seq_id(seq_id);
    anum_set_qos_for_seq(seq_id);
    anum_log_qos("ingest_enter");

    if (!prompt_utf8) return -2;

    std::string fragment(prompt_utf8);
    if (fragment.empty()) return -2;

    const bool looks_like_raw_scaffold = !anum_contains_any_chat_marker(fragment);
    const std::string raw_scaffold_source = fragment;
    if (looks_like_raw_scaffold) {
        fragment = anum_format_raw_scaffold_for_runtime(fragment);
        if (fragment.empty()) return -2;
    }

    std::unique_lock<std::mutex> gen_lock(g_generate_mutex);
    a->abort_requested.store(false, std::memory_order_relaxed);

    if (!a->ctx && !anum_init_context_from_model(a)) {
        return -7;
    }

    if (looks_like_raw_scaffold) {
        const size_t h = std::hash<std::string>{}(raw_scaffold_source);

        if (a->has_live_state_by_seq[seq_id] && a->last_raw_scaffold_hash_by_seq[seq_id] == h) {
            ANUM_EPRINTF("[anum_llama] ingest_ex skip duplicate raw scaffold seq=%d\n", (int)seq_id);
            ANUM_EFLUSH();
            return 0;
        }

        if (a->has_live_state_by_seq[seq_id] &&
            a->last_raw_scaffold_hash_by_seq[seq_id] != 0 &&
            a->last_raw_scaffold_hash_by_seq[seq_id] != h) {
            ANUM_EPRINTF("[anum_llama] ingest_ex scaffold changed -> clearing seq=%d\n", (int)seq_id);
            ANUM_EFLUSH();

            if (a->ctx) {
                llama_memory_t mem = llama_get_memory(a->ctx);
                if (mem) {
                    llama_memory_seq_rm(mem, seq_id, 0, -1);
                }
            }
            anum_clear_seq_runtime_state(a, seq_id);
        }

        a->last_raw_scaffold_hash_by_seq[seq_id] = h;
    }

    std::vector<llama_token> tokens;
    if (!tokenize_prompt(a->model, fragment, tokens)) {
        logf("[anum_llama] ingest_ex tokenize failed");
        return -3;
    }

    const int32_t reserve_for_gen = 512;
    const int32_t max_prompt_tokens = std::max<int32_t>(0, a->n_ctx - reserve_for_gen);
    if ((int32_t)tokens.size() > max_prompt_tokens) {
        tokens.resize((size_t)max_prompt_tokens);
    }

    llama_pos new_pos = a->cur_pos_by_seq[seq_id];
    int32_t last_logits_idx = -1;
    const int32_t rc = anum_decode_token_span(
        a,
        tokens,
        0,
        a->cur_pos_by_seq[seq_id],
        seq_id,
        /*request_logits_on_last=*/true,
        new_pos,
        last_logits_idx
    );
    if (rc != 0) return rc;

    a->cur_pos_by_seq[seq_id] = new_pos;
    a->has_live_state_by_seq[seq_id] = true;
    a->has_live_logits_by_seq[seq_id] = !tokens.empty();
    a->last_logits_index_by_seq[seq_id] = !tokens.empty() ? last_logits_idx : -1;
    if (!looks_like_raw_scaffold) {
        a->last_raw_scaffold_hash_by_seq[seq_id] = 0;
    }

    ANUM_EPRINTF(
        "[anum_llama] ingest_ex OK seq=%d tokens=%zu cur_pos=%d last_logits_idx=%d\n",
        (int)seq_id, tokens.size(), (int)a->cur_pos_by_seq[seq_id], (int)a->last_logits_index_by_seq[seq_id]
    );
    ANUM_EFLUSH();

    return 0;
}

int32_t anum_llama_ingest(
    anum_llama_t ctx,
    const char* prompt_utf8
) {
    return anum_llama_ingest_ex(ctx, prompt_utf8, 0);
}

int32_t anum_llama_continue_ex(
    anum_llama_t ctx,
    const char* prompt_prefix_utf8,
    int32_t max_tokens,
    int32_t seq_id,
    anum_token_cb cb,
    void* user_data
) {
    auto* a = (anum_ctx*)ctx;
    if (!a || !a->model || !a->sampler) return -1;

    seq_id = anum_clamp_seq_id(seq_id);
    anum_set_qos_for_seq(seq_id);
    anum_log_qos("continue_enter");

    std::unique_lock<std::mutex> gen_lock(g_generate_mutex);
    a->abort_requested.store(false, std::memory_order_relaxed);

    if (!a->ctx && !anum_init_context_from_model(a)) {
        return -7;
    }

    if (prompt_prefix_utf8 && prompt_prefix_utf8[0] != '\0') {
        const std::string prefix(prompt_prefix_utf8);
        const int32_t rc_prefix = anum_ingest_prefix_fragment_locked(a, prefix, seq_id, max_tokens);
        if (rc_prefix != 0) {
            return rc_prefix;
        }
    }

    return anum_generate_from_current_state_locked(a, max_tokens, seq_id, cb, user_data);
}

int32_t anum_llama_continue(
    anum_llama_t ctx,
    const char* prompt_prefix_utf8,
    int32_t max_tokens,
    anum_token_cb cb,
    void* user_data
) {
    return anum_llama_continue_ex(ctx, prompt_prefix_utf8, max_tokens, 0, cb, user_data);
}

int32_t anum_llama_generate_ex_flags_ext(
    anum_llama_t ctx,
    const char* prompt_utf8,
    const char* scaffold_utf8_nullable,
    int32_t max_tokens,
    int32_t seq_id,
    uint32_t flags,
    anum_token_cb cb,
    void* user_data
) {
    auto* a = (anum_ctx*)ctx;
    if (!a || !a->model || !a->sampler) return -1;

    seq_id = anum_clamp_seq_id(seq_id);
    anum_set_qos_for_seq(seq_id);
    anum_log_qos("generate_enter");

    std::unique_lock<std::mutex> gen_lock(g_generate_mutex);
    a->abort_requested.store(false, std::memory_order_relaxed);

    if (!a->ctx && !anum_init_context_from_model(a)) {
        return -7;
    }

    if (a->pending_checkpoint_regenerate) {
        a->pending_checkpoint_regenerate = false;

        std::string formatted_cp;
        if (!anum_prepare_formatted_prompt(prompt_utf8, formatted_cp)) {
            struct DoneOnce {
                anum_token_cb cb;
                void* ud;
                bool done;
                DoneOnce(anum_token_cb cb_, void* ud_) : cb(cb_), ud(ud_), done(false) {}
                void finish() { if (!done) { done = true; if (cb) cb("", ud); } }
                ~DoneOnce() { if (!done && cb) cb("", ud); }
            } done(cb, user_data);
            done.finish();
            return -2;
        }

        max_tokens = clamp_i32(max_tokens, 0, 2048);

        std::vector<llama_token> prompt_tokens_cp;
        if (!tokenize_prompt(a->model, formatted_cp, prompt_tokens_cp)) {
            struct DoneOnce {
                anum_token_cb cb;
                void* ud;
                bool done;
                DoneOnce(anum_token_cb cb_, void* ud_) : cb(cb_), ud(ud_), done(false) {}
                void finish() { if (!done) { done = true; if (cb) cb("", ud); } }
                ~DoneOnce() { if (!done && cb) cb("", ud); }
            } done(cb, user_data);
            done.finish();
            return -3;
        }

        const int32_t reserve_cp = std::min<int32_t>(max_tokens, 512);
        const int32_t max_prompt_tokens_cp = std::max<int32_t>(0, a->n_ctx - reserve_cp);

        if ((int32_t)prompt_tokens_cp.size() > max_prompt_tokens_cp) {
            int32_t keep_head = std::min<int32_t>(256, std::max<int32_t>(32, max_prompt_tokens_cp / 4));
            keep_head = std::min<int32_t>(keep_head, max_prompt_tokens_cp);
            const int32_t keep_tail = std::max<int32_t>(0, max_prompt_tokens_cp - keep_head);

            std::vector<llama_token> trimmed_cp;
            trimmed_cp.reserve((size_t)max_prompt_tokens_cp);
            trimmed_cp.insert(trimmed_cp.end(), prompt_tokens_cp.begin(), prompt_tokens_cp.begin() + keep_head);
            if (keep_tail > 0) {
                trimmed_cp.insert(trimmed_cp.end(), prompt_tokens_cp.end() - keep_tail, prompt_tokens_cp.end());
            }
            prompt_tokens_cp.swap(trimmed_cp);
        }

        const uint64_t fnv_cp = anum_fnv1a64_tokens(prompt_tokens_cp);
        return anum_checkpoint_regenerate_locked(a, prompt_tokens_cp, fnv_cp, max_tokens, seq_id, cb, user_data);
    }

    if (a->pending_scaffold_checkpoint_replay) {
        a->pending_scaffold_checkpoint_replay = false;
        max_tokens = clamp_i32(max_tokens, 0, 2048);
        return anum_scaffold_checkpoint_replay_locked(
            a,
            prompt_utf8,
            scaffold_utf8_nullable ? scaffold_utf8_nullable : "",
            flags,
            max_tokens,
            seq_id,
            cb,
            user_data
        );
    }

    std::string formatted;
    if (!anum_prepare_formatted_prompt(prompt_utf8, formatted)) {
        struct DoneOnce {
            anum_token_cb cb;
            void* ud;
            bool done;
            DoneOnce(anum_token_cb cb_, void* ud_) : cb(cb_), ud(ud_), done(false) {}
            void finish() { if (!done) { done = true; if (cb) cb("", ud); } }
            ~DoneOnce() { if (!done && cb) cb("", ud); }
        } done(cb, user_data);
        done.finish();
        return -2;
    }

    max_tokens = clamp_i32(max_tokens, 0, 2048);

    std::vector<llama_token> prompt_tokens;
    if (!tokenize_prompt(a->model, formatted, prompt_tokens)) {
        struct DoneOnce {
            anum_token_cb cb;
            void* ud;
            bool done;
            DoneOnce(anum_token_cb cb_, void* ud_) : cb(cb_), ud(ud_), done(false) {}
            void finish() { if (!done) { done = true; if (cb) cb("", ud); } }
            ~DoneOnce() { if (!done && cb) cb("", ud); }
        } done(cb, user_data);
        done.finish();
        return -3;
    }

    const int32_t reserve_for_gen = std::min<int32_t>(max_tokens, 512);
    const int32_t max_prompt_tokens = std::max<int32_t>(0, a->n_ctx - reserve_for_gen);

    if ((int32_t)prompt_tokens.size() > max_prompt_tokens) {
        int32_t keep_head = std::min<int32_t>(256, std::max<int32_t>(32, max_prompt_tokens / 4));
        keep_head = std::min<int32_t>(keep_head, max_prompt_tokens);
        const int32_t keep_tail = std::max<int32_t>(0, max_prompt_tokens - keep_head);

        std::vector<llama_token> trimmed;
        trimmed.reserve((size_t)max_prompt_tokens);
        trimmed.insert(trimmed.end(), prompt_tokens.begin(), prompt_tokens.begin() + keep_head);
        if (keep_tail > 0) {
            trimmed.insert(trimmed.end(), prompt_tokens.end() - keep_tail, prompt_tokens.end());
        }
        prompt_tokens.swap(trimmed);
    }

    size_t prefix_len = 0;
    size_t raw_common_prefix_tokens = 0;
    if (a->enable_prefix_cache && !a->last_prompt_tokens_by_seq[seq_id].empty()) {
        raw_common_prefix_tokens = common_prefix_len(a->last_prompt_tokens_by_seq[seq_id], prompt_tokens);
        prefix_len = raw_common_prefix_tokens;
        if (prefix_len < 64) prefix_len = 0;
    }

    const size_t prompt_token_count = prompt_tokens.size();
    const bool logits_valid_for_prefix_only =
        a->has_live_logits_by_seq[seq_id] && (a->last_logits_index_by_seq[seq_id] >= 0);

    int forced_last_token_redecode = 0;
    // If we would reuse the entire prompt KV with zero tail tokens to decode, sampling needs valid logits.
    // After a prior generation, logits may be cleared (-8 in continue path); force one tail token re-decode.
    if (a->enable_prefix_cache && prompt_token_count > 0 && prefix_len >= prompt_token_count &&
        !logits_valid_for_prefix_only) {
        if (prefix_len > 0) {
            prefix_len = prompt_token_count - 1;
            forced_last_token_redecode = 1;
        }
    }

    const int reused_prefix_flag =
        ((prefix_len > 0) || forced_last_token_redecode) ? 1 : 0;

    ANUM_EPRINTF(
        "[LlamaPrefixCache] rawCommonPrefixTokens=%zu effectivePrefixTokens=%zu promptTokens=%zu reusedPrefix=%d forcedLastTokenRedecode=%d logitsValid=%d seq=%d cache=%d\n",
        raw_common_prefix_tokens,
        (size_t)prefix_len,
        prompt_token_count,
        reused_prefix_flag,
        forced_last_token_redecode,
        logits_valid_for_prefix_only ? 1 : 0,
        (int)seq_id,
        a->enable_prefix_cache ? 1 : 0
    );
    ANUM_EFLUSH();

    llama_memory_t mem = llama_get_memory(a->ctx);
    if (mem) {
        if (prefix_len > 0) {
            llama_memory_seq_rm(mem, seq_id, (llama_pos)prefix_len, -1);
        } else {
            llama_memory_seq_rm(mem, seq_id, 0, -1);
        }
        llama_perf_context_reset(a->ctx);
    } else {
        if (a->ctx) {
            llama_free(a->ctx);
            a->ctx = nullptr;
        }
        anum_clear_seq_runtime_state(a, seq_id);
        if (!anum_init_context_from_model(a)) {
            struct DoneOnce {
                anum_token_cb cb;
                void* ud;
                bool done;
                DoneOnce(anum_token_cb cb_, void* ud_) : cb(cb_), ud(ud_), done(false) {}
                void finish() { if (!done) { done = true; if (cb) cb("", ud); } }
                ~DoneOnce() { if (!done && cb) cb("", ud); }
            } done(cb, user_data);
            done.finish();
            return -7;
        }
        prefix_len = 0;
    }

    llama_pos cur_pos = (llama_pos)prefix_len;
    int32_t last_logits_idx = -1;
    int32_t rc_ingest = 0;

    const bool capture_prompt_flag = (flags & ANUM_GENERATE_EX_FLAG_CAPTURE_PROMPT_CHECKPOINT) != 0;
    const bool capture_scaffold_flag = (flags & ANUM_GENERATE_EX_FLAG_CAPTURE_SCAFFOLD_CHECKPOINT) != 0;
    const bool use_scaffold_split =
        capture_scaffold_flag &&
        scaffold_utf8_nullable &&
        scaffold_utf8_nullable[0] != '\0';

    const size_t n_prompt_tok = prompt_tokens.size();

    if (use_scaffold_split) {
        const std::string scaff_prefix(scaffold_utf8_nullable);
        if (formatted.size() < scaff_prefix.size() || formatted.compare(0, scaff_prefix.size(), scaff_prefix) != 0) {
            struct DoneOnce {
                anum_token_cb cb;
                void* ud;
                bool done;
                DoneOnce(anum_token_cb cb_, void* ud_) : cb(cb_), ud(ud_), done(false) {}
                void finish() { if (!done) { done = true; if (cb) cb("", ud); } }
                ~DoneOnce() { if (!done && cb) cb("", ud); }
            } done(cb, user_data);
            done.finish();
            return -5;
        }

        std::vector<llama_token> scaffold_tokens;
        if (!tokenize_prompt(a->model, scaff_prefix, scaffold_tokens)) {
            struct DoneOnce {
                anum_token_cb cb;
                void* ud;
                bool done;
                DoneOnce(anum_token_cb cb_, void* ud_) : cb(cb_), ud(ud_), done(false) {}
                void finish() { if (!done) { done = true; if (cb) cb("", ud); } }
                ~DoneOnce() { if (!done && cb) cb("", ud); }
            } done(cb, user_data);
            done.finish();
            return -3;
        }

        if (scaffold_tokens.size() > prompt_tokens.size()) {
            struct DoneOnce {
                anum_token_cb cb;
                void* ud;
                bool done;
                DoneOnce(anum_token_cb cb_, void* ud_) : cb(cb_), ud(ud_), done(false) {}
                void finish() { if (!done) { done = true; if (cb) cb("", ud); } }
                ~DoneOnce() { if (!done && cb) cb("", ud); }
            } done(cb, user_data);
            done.finish();
            return -5;
        }

        for (size_t i = 0; i < scaffold_tokens.size(); ++i) {
            if (prompt_tokens[i] != scaffold_tokens[i]) {
                struct DoneOnce {
                    anum_token_cb cb;
                    void* ud;
                    bool done;
                    DoneOnce(anum_token_cb cb_, void* ud_) : cb(cb_), ud(ud_), done(false) {}
                    void finish() { if (!done) { done = true; if (cb) cb("", ud); } }
                    ~DoneOnce() { if (!done && cb) cb("", ud); }
                } done(cb, user_data);
                done.finish();
                return -5;
            }
        }

        llama_pos after_scaffold = cur_pos;
        int32_t junk_sc = -1;
        rc_ingest = anum_decode_token_span(
            a,
            scaffold_tokens,
            0,
            cur_pos,
            seq_id,
            /*request_logits_on_last=*/false,
            after_scaffold,
            junk_sc
        );

        if (rc_ingest != 0) {
            struct DoneOnce {
                anum_token_cb cb;
                void* ud;
                bool done;
                DoneOnce(anum_token_cb cb_, void* ud_) : cb(cb_), ud(ud_), done(false) {}
                void finish() { if (!done) { done = true; if (cb) cb("", ud); } }
                ~DoneOnce() { if (!done && cb) cb("", ud); }
            } done(cb, user_data);
            done.finish();
            return rc_ingest;
        }

        anum_scaffold_checkpoint_save_from_current(a, seq_id, scaffold_tokens, after_scaffold);

        rc_ingest = anum_decode_dynamic_tail_with_prompt_checkpoint_capture(
            a,
            seq_id,
            prompt_tokens,
            scaffold_tokens.size(),
            after_scaffold,
            capture_prompt_flag,
            cur_pos,
            last_logits_idx
        );
    } else if (capture_prompt_flag && n_prompt_tok > 0) {
        rc_ingest = anum_decode_dynamic_tail_with_prompt_checkpoint_capture(
            a,
            seq_id,
            prompt_tokens,
            0,
            cur_pos,
            /*capture_prompt_checkpoint=*/true,
            cur_pos,
            last_logits_idx
        );
    } else {
        rc_ingest = anum_decode_token_span(
            a,
            prompt_tokens,
            prefix_len,
            cur_pos,
            seq_id,
            /*request_logits_on_last=*/true,
            cur_pos,
            last_logits_idx
        );
    }

    if (rc_ingest != 0) {
        struct DoneOnce {
            anum_token_cb cb;
            void* ud;
            bool done;
            DoneOnce(anum_token_cb cb_, void* ud_) : cb(cb_), ud(ud_), done(false) {}
            void finish() { if (!done) { done = true; if (cb) cb("", ud); } }
            ~DoneOnce() { if (!done && cb) cb("", ud); }
        } done(cb, user_data);
        done.finish();
        return rc_ingest;
    }

    a->last_prompt_tokens_by_seq[seq_id] = prompt_tokens;
    a->cur_pos_by_seq[seq_id] = cur_pos;
    a->has_live_state_by_seq[seq_id] = true;
    a->has_live_logits_by_seq[seq_id] = !prompt_tokens.empty();
    a->last_logits_index_by_seq[seq_id] = !prompt_tokens.empty() ? last_logits_idx : -1;
    a->last_raw_scaffold_hash_by_seq[seq_id] = 0;

    if (max_tokens == 0) {
        if (cb) cb("", user_data);
        return 0;
    }

    return anum_generate_from_current_state_locked(a, max_tokens, seq_id, cb, user_data);
}

int32_t anum_llama_generate_ex_flags(
    anum_llama_t ctx,
    const char* prompt_utf8,
    int32_t max_tokens,
    int32_t seq_id,
    uint32_t flags,
    anum_token_cb cb,
    void* user_data
) {
    return anum_llama_generate_ex_flags_ext(ctx, prompt_utf8, nullptr, max_tokens, seq_id, flags, cb, user_data);
}

int32_t anum_llama_generate_ex(
    anum_llama_t ctx,
    const char* prompt_utf8,
    int32_t max_tokens,
    int32_t seq_id,
    anum_token_cb cb,
    void* user_data
) {
    return anum_llama_generate_ex_flags(ctx, prompt_utf8, max_tokens, seq_id, 0, cb, user_data);
}

int32_t anum_llama_generate(
    anum_llama_t ctx,
    const char* prompt_utf8,
    int32_t max_tokens,
    anum_token_cb cb,
    void* user_data
) {
    return anum_llama_generate_ex(ctx, prompt_utf8, max_tokens, 0, cb, user_data);
}
