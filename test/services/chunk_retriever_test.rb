require "test_helper"

class ChunkRetrieverTest < ActiveSupport::TestCase
  setup { @document = embedded_document }

  # AC1. Only one embedding response is queued, and FakeGeminiTransport raises on
  # an unexpected extra call — so a second embed fails loudly here rather than
  # quietly passing.
  test "the anchor is embedded once, however many documents are summarised" do
    stub_gemini(gemini_embeddings(1)) do |fake|
      ChunkRetriever.new(@document).anchor_passages
      ChunkRetriever.new(embedded_document).anchor_passages

      assert_equal 1, fake.call_count, "the anchor should be embedded once and reused"
    end
  end

  # AC2. The cache lives on the anchor path alone. A question is different every
  # time, so caching one would answer the wrong question — this is the assertion
  # that the two paths did not get merged.
  test "a question is embedded every time it is asked" do
    stub_gemini(gemini_embeddings(1), gemini_embeddings(1)) do |fake|
      ChunkRetriever.new(@document).nearest("what is the deductible", limit: 3)
      ChunkRetriever.new(@document).nearest("who do I call", limit: 3)

      assert_equal 2, fake.call_count
    end
  end

  test "a cached anchor does not satisfy a question" do
    stub_gemini(gemini_embeddings(1), gemini_embeddings(1)) do |fake|
      ChunkRetriever.new(@document).anchor_passages
      ChunkRetriever.new(@document).nearest("what is the deductible", limit: 3)

      assert_equal 2, fake.call_count, "the question must not be served the anchor's vector"
    end
  end

  # AC3. The constant is frozen, so composing the key is testable where swapping
  # the model is not. What matters is that the model is in it at all.
  test "the cache key carries the embedding model" do
    assert_includes ChunkRetriever::ANCHOR_CACHE_KEY, GeminiClient::EMBEDDING_MODEL
  end

  # AC4, as far as it is reachable. GeminiClient rejects any vector that is not
  # exactly EMBEDDING_DIMENSIONS long, so it never *returns* a blank one — it
  # raises instead. The thing worth asserting is therefore not "a blank is not
  # cached" but "a failure leaves the cache empty", so the next upload retries
  # rather than being served nothing for a week.
  test "a failed embedding leaves the cache empty" do
    stub_gemini({ "embeddings" => [] }) do
      assert_raises(ProcessingError::ServiceUnavailable) do
        ChunkRetriever.new(@document).anchor_passages
      end
    end

    assert_nil Rails.cache.read(ChunkRetriever::ANCHOR_CACHE_KEY)
  end

  test "no passages are fetched when none are asked for" do
    stub_gemini do |fake|
      assert_empty ChunkRetriever.new(@document).anchor_passages(limit: 0)

      assert_equal 0, fake.call_count, "a limit of zero should not reach the model"
    end
  end

  private
    def embedded_document
      Document.create!(status: "summarizing", title: "doc.pdf").tap do |document|
        6.times do |i|
          document.chunks.create!(
            content: "passage #{i} about coverage and what you pay " * 20,
            position: i, page: i + 1,
            embedding: Array.new(GeminiClient::EMBEDDING_DIMENSIONS) { rand }
          )
        end
      end
    end
end
