#pragma once
#include <stdint.h>
#include <stddef.h>

#if defined(__clang__) && __has_feature(nullability)
#define ANUM_NONNULL _Nonnull
#define ANUM_NULLABLE _Nullable
#else
#define ANUM_NONNULL
#define ANUM_NULLABLE
#endif

#ifdef __cplusplus
extern "C" {
#endif

#if defined(__clang__) && __has_feature(nullability)
#pragma clang assume_nonnull begin
#endif

typedef void* anum_llama_t;

typedef struct {
    int32_t n_ctx;
    int32_t n_threads;
    int32_t n_batch;
    float temperature;
    int32_t top_k;
    float top_p;
    int32_t seed;
} anum_llama_params_t;

typedef void (*anum_token_cb)(const char* ANUM_NULLABLE utf8_piece, void* ANUM_NONNULL user_data);

typedef enum {
    ANUM_RESET_NONE = 0,
    ANUM_RESET_KV   = 1,
    ANUM_RESET_FULL = 2,
    ANUM_RESET_PROMPT_CHECKPOINT_REGENERATE = 3,
    ANUM_RESET_SCAFFOLD_CHECKPOINT_REPLAY = 4,
} anum_reset_mode_t;

/** Bitmask for `anum_llama_generate_ex_flags_ext`. After prompt ingest, snapshot seq state for Direct Chat regenerate. */
#define ANUM_GENERATE_EX_FLAG_CAPTURE_PROMPT_CHECKPOINT (1u << 0)
#define ANUM_GENERATE_EX_FLAG_CAPTURE_SCAFFOLD_CHECKPOINT (1u << 1)

anum_llama_t ANUM_NULLABLE anum_llama_create(const char* ANUM_NONNULL model_path, anum_llama_params_t p);
void anum_llama_destroy(anum_llama_t ctx);

int32_t anum_llama_abort(anum_llama_t ctx);
int32_t anum_llama_clear_abort(anum_llama_t ctx);
int32_t anum_llama_reset(anum_llama_t ctx, anum_reset_mode_t mode);

// Full path: tokenize + ingest missing tail + generate.
// When `scaffold_utf8_nullable` is non-NULL, it must be a UTF-8 prefix of `prompt_utf8` (stable Direct Chat scaffold).
int32_t anum_llama_generate_ex_flags_ext(
    anum_llama_t ctx,
    const char* ANUM_NONNULL prompt_utf8,
    const char* ANUM_NULLABLE scaffold_utf8_nullable,
    int32_t max_tokens,
    int32_t seq_id,
    uint32_t flags,
    anum_token_cb ANUM_NONNULL cb,
    void* ANUM_NONNULL user_data
);

int32_t anum_llama_generate_ex_flags(
    anum_llama_t ctx,
    const char* ANUM_NONNULL prompt_utf8,
    int32_t max_tokens,
    int32_t seq_id,
    uint32_t flags,
    anum_token_cb ANUM_NONNULL cb,
    void* ANUM_NONNULL user_data
);

int32_t anum_llama_generate_ex(
    anum_llama_t ctx,
    const char* ANUM_NONNULL prompt_utf8,
    int32_t max_tokens,
    int32_t seq_id,
    anum_token_cb ANUM_NONNULL cb,
    void* ANUM_NONNULL user_data
);

// Backwards-compatible seq0 wrapper
int32_t anum_llama_generate(
    anum_llama_t ctx,
    const char* ANUM_NONNULL prompt_utf8,
    int32_t max_tokens,
    anum_token_cb ANUM_NONNULL cb,
    void* ANUM_NONNULL user_data
);

// New: ingest only, no generation.
// Used for scaffold prime / runtime-owned state building.
int32_t anum_llama_ingest_ex(
    anum_llama_t ctx,
    const char* ANUM_NONNULL prompt_utf8,
    int32_t seq_id
);

// Backwards-compatible seq0 wrapper
int32_t anum_llama_ingest(
    anum_llama_t ctx,
    const char* ANUM_NONNULL prompt_utf8
);

// New: continue generation from existing KV/state without replaying full prompt.
// Assumes logits/state already exist for this seq_id.
int32_t anum_llama_continue_ex(
    anum_llama_t ctx,
    const char* ANUM_NONNULL prompt_prefix_utf8,
    int32_t max_tokens,
    int32_t seq_id,
    anum_token_cb ANUM_NONNULL cb,
    void* ANUM_NONNULL user_data
);

// Backwards-compatible seq0 wrapper
int32_t anum_llama_continue(
    anum_llama_t ctx,
    const char* ANUM_NONNULL prompt_prefix_utf8,
    int32_t max_tokens,
    anum_token_cb ANUM_NONNULL cb,
    void* ANUM_NONNULL user_data
);

#if defined(__clang__) && __has_feature(nullability)
#pragma clang assume_nonnull end
#endif

#ifdef __cplusplus
}
#endif
