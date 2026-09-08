# Feature Spec: cache-anchor-vector

## Summary

`GENERIC_ANCHOR` is a frozen constant, so its embedding is the same vector on every
upload — yet `ChunkRetriever#nearest` asks Gemini for it again each time. Caching it
makes summarising one call instead of two, a third off the cost of uploading a small
document.

## Requirements

- R1 The anchor's vector is fetched from Gemini at most once per model, not once per document.
- R2 A cache miss still works: an unavailable cache costs a call, never an error.
- R3 The cache key includes the embedding model, so a model change cannot serve stale vectors.
- R4 Question embedding is unaffected — every question is different and must not be cached.
- R5 Summaries are unchanged in content; this is a cost change, not a behaviour change.

## Non-Goals

- Caching answers, summaries, or question embeddings.
- Precomputing the vector at boot or committing it to the repository.
- Changing `GENERIC_ANCHOR`'s wording or `SUMMARY_PASSAGES`.

## Edge Cases

- Cache empty (fresh deploy, evicted key) → one embed call, then cached.
- Redis unreachable → `Rails.cache.fetch` runs the block; behaviour matches today.
- `EMBEDDING_MODEL` changed → different key, so the old vector is never served.
- Gemini returns nothing for the anchor → nothing is cached, and `nearest` returns `[]` as now.

## Acceptance Criteria

- AC1 Two summaries in a row make one anchor embed call, not two — asserted on the fake transport.
- AC2 A question still embeds every time, however many questions are asked.
- AC3 The cached value is not served when `EMBEDDING_MODEL` differs.
- AC4 A blank response from Gemini is not cached.
- AC5 `bin/rails test`, `bin/rubocop` and Brakeman pass.

## Resolved Decisions

- **D1** Cache in `Rails.cache`, which is the Render Key Value instance. Shared between
  Puma and Sidekiq, and survives a restart — a process-local constant would pay the call
  again in every process on every deploy.
- **D2** Expire after a week. Never would be correct while the model is pinned, but a TTL
  costs one call a week and removes a whole class of "stale vector" problems we would otherwise
  have to reason about.
- **D3** The key carries `EMBEDDING_MODEL`, so a model change misses rather than serving a
  vector from the wrong space.

### Size, since it goes in Redis

The vector is 3072 floats — tens of kilobytes serialised, in a single key. Negligible
against the free instance, but worth noting: until now Redis held only integer counters and
job payloads, so this is the first sizeable value the cache carries.
