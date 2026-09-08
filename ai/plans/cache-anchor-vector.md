# Plan: cache-anchor-vector

Spec: `ai/feature-specs/cache-anchor-vector.md` — D1–D3 resolved, no open questions.

## Confirmed Decisions

- **D1** `Rails.cache` — shared by Puma and Sidekiq, and survives a restart.
- **D2** One-week TTL — one call a week buys out a class of stale-vector reasoning.
- **D3** `EMBEDDING_MODEL` in the key — a model change misses instead of serving a vector
  from the wrong space.

## Approach

- **Split the two paths rather than add a flag.** `nearest` stays exactly as it is and
  keeps embedding every time; `anchor_passages` stops calling it and uses a cached vector.
- That makes R4 structural: a question physically cannot reach the cache, because the
  cached value lives on the anchor path only.
- `Rails.cache.fetch(key, expires_in: 1.week, skip_nil: true)` with `.presence` on the
  result — a blank embedding becomes `nil`, and `skip_nil` keeps it out of the cache (AC4).
- Key is `"chunk_retriever/anchor/#{GeminiClient::EMBEDDING_MODEL}"`, so D3 is visible in
  the key rather than remembered in a comment.
- Nothing needs a fallback for a dead cache: `Rails.cache.fetch` runs the block on a miss
  *or* an error, which is exactly today's behaviour (R2).

## Files Touched

- `app/services/chunk_retriever.rb` — `anchor_passages` uses a new private `anchor_vector`;
  `nearest` untouched.
- `test/services/chunk_retriever_test.rb` — the caching cases.
- `CHANGELOG.md`.

## Checkpoints

1. **Cache the anchor.** One method, one call site, the tests.
   → verify: two summaries in a row make one embed call, not two; a question still embeds
   every time; a blank response is not cached; `bin/rails test`, `bin/rubocop`,
   `bin/brakeman` green.
   *Commit: "Stop re-embedding the same anchor query on every upload"*

## Test Plan

- **AC1:** run `anchor_passages` twice under one `stub_gemini`, queuing only *one* embedding
  response. `FakeGeminiTransport` raises on an unexpected extra call, so a second embed
  fails loudly rather than quietly passing.
- **AC2:** two different questions through `nearest` make two embed calls — the assertion
  that the cache did not leak onto the question path.
- **AC3:** the cache key contains `GeminiClient::EMBEDDING_MODEL`, asserted directly. The
  constant is frozen, so composing the key is testable where swapping the model is not.
- **AC4:** an embedding response with no vectors leaves the cache empty — call twice, get
  two requests.
- `Rails.cache` in test is `:memory_store` and `test_helper` already clears it in setup, so
  these need no Redis and cannot leak between tests. **Verified, not assumed.**
- Tooling: `bin/rails test`, `bin/rubocop`, `bin/brakeman`. No system tests — nothing visual.

## Risks / Rollback

- **A wrong vector would silently degrade every summary** rather than fail → the key carries
  the model, and the TTL bounds any mistake to a week.
- **The cached value is now the app's only large Redis value** — 3072 floats in one key,
  where everything else is an integer counter. Negligible in size; worth knowing it changes
  what Redis holds.
- **A stale vector after a model upgrade** → impossible by construction, since the model is
  part of the key. This is the one failure worth designing out rather than monitoring.
- **Rollback** is deleting one method and restoring one line. No migration, no schema, no
  data, and the cache key simply stops being read.
