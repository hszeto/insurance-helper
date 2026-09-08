# Finds the passages of a document most likely to answer something.
#
# This is the piece that replaces sending the document to the model. Everything
# downstream — the summary, every answer — works from a handful of passages
# chosen here, which is why the whole document never goes over the wire.
class ChunkRetriever
  # How many passages a summary is built from. Enough to cover a document's
  # shape without becoming a long prompt.
  SUMMARY_PASSAGES = 5

  # Language that tends to sit near the parts of a document that describe the
  # whole of it. Nothing about this is domain-specific: it is a "where does this
  # document explain itself" query, not a question about the subject matter.
  GENERIC_ANCHOR = "executive summary, conclusion, abstract, overview, main findings, " \
                   "purpose, scope, key points".freeze

  # The anchor is frozen, so its vector is the same on every upload. Caching it
  # makes summarising one call instead of two.
  #
  # A week rather than forever: while the model is pinned, forever would be
  # correct, but one call a week is cheaper than reasoning about when a cached
  # vector might have gone stale (D2).
  ANCHOR_TTL = 1.week

  # The model belongs in the key, not in a comment. A future gemini-embedding-002
  # then misses rather than being handed a vector from a different space (D3).
  ANCHOR_CACHE_KEY = "chunk_retriever/anchor/#{GeminiClient::EMBEDDING_MODEL}".freeze

  def initialize(document, client: GeminiClient.new)
    @document = document
    @client = client
  end

  def nearest(query, limit:)
    return [] if limit < 1

    vector = @client.embed([ query ]).first
    return [] if vector.blank?

    by_similarity(vector, limit)
  end

  # The passages a summary should be built from (R5.1).
  #
  # Deliberately not routed through #nearest any more. A question must never be
  # cached — every one is different — and keeping the cache on this path alone
  # makes that structural rather than a rule someone has to remember.
  def anchor_passages(limit: SUMMARY_PASSAGES)
    return [] if limit < 1

    vector = anchor_vector
    return [] if vector.blank?

    by_similarity(vector, limit)
  end

  private
    # `presence` and `skip_nil` together keep an empty response out of the cache:
    # a blank embedding would otherwise be served for a week, silently summarising
    # every document from nothing.
    def anchor_vector
      Rails.cache.fetch(ANCHOR_CACHE_KEY, expires_in: ANCHOR_TTL, skip_nil: true) do
        @client.embed([ GENERIC_ANCHOR ]).first.presence
      end
    end

    def by_similarity(vector, limit)
      @document.chunks
               .embedded
               .nearest_neighbors(:embedding, vector, distance: "cosine")
               .limit(limit)
               .to_a
    end
end
