# Changelog

Notable changes to this project.

## [0.5.1] - 2026-09-05

### Changed

- **Summarising costs one Gemini call instead of two.** The query used to find a
  document's overview passages is a frozen constant, so its vector is identical
  on every upload — and was being fetched again for each one. It is now cached
  for a week, keyed by the embedding model so a model change misses rather than
  serving a vector from a different space.
- For a small document that takes uploading from three calls to two.

### Notes

- Questions are still embedded every time, as they must be: each one is
  different. The cache sits on the anchor path alone rather than behind a flag,
  so a question cannot reach it, and a test asserts that.
- This is the first sizeable value in the cache — 3072 floats in one key, where
  everything else there is an integer counter.

## [0.5.0] - 2026-09-05

### Added

- **A record of how much the app is used**, which survives the documents it
  counts. Every document is deleted after thirty minutes and the file's size
  lives on the Active Storage blob that goes with it, so until now there was no
  way to know afterwards that anything had happened at all.
- `usage_events` keeps a size, a moment, and a daily-rotating HMAC of the
  visitor's address. The address is never stored, and yesterday's hash cannot be
  matched to today's — countable without being identifying.
- Refused uploads are counted separately from accepted ones, including
  rate-limited attempts, which never enter the action and are counted at the
  limiter instead.
- **`/health`** reports the figures as a run of unlabelled numbers. It is public
  and unauthenticated: a count means nothing to someone who does not know what is
  being counted, and that is cheaper than a login on an app with no accounts.

### Notes

- `/up` is unchanged. It is Rails' own health check and Render polls it as the
  service health check.
- The new endpoint inherits from `ActionController::Base`, not
  `ApplicationController`, so `allow_browser versions: :modern` cannot turn away
  a monitor that sends an old browser's User-Agent. A test asserts that the same
  User-Agent gets 406 on a page and 200 here.
- These rows are the first thing in this app that never expires. At the current
  rate limit that is a few thousand a year.

## [0.4.0] - 2026-09-05

### Changed

- **The home page explains itself.** The heading, the lead and the upload field now
  sit in the same tinted panel the chat screen uses, so the two screens read as one
  app rather than two designs.
- **A "How it works" section**: add a PDF and it is validated, ask a question and get
  an answer with the page number, and the document is deleted after thirty minutes.
  The deletion promise used to be a grey footnote; it is now one of the three things
  the page actually says.
- **The app has a logo and a name on screen.** A page mark with one line picked
  out — the passage that matters, which is the whole idea of the app — beside the
  name "PDF-RAG", on every page and linking back to a fresh upload.
- **Each step carries an icon**: a document, a lightbulb, a waste bin. They replace
  the plain numerals rather than joining them.

### Fixed

- **The favicon was Rails' placeholder** — a red circle — and is now the app's own
  mark. `public/icon.png` is still the placeholder and needs regenerating.

### Notes

- Icons and the logo are inline SVG drawn with `currentColor`; no icon library, no
  external requests, and no new colours.
- No new colours. The palette is contrast-verified in `palette_test.rb`, and that file
  is untouched — the panel and step surfaces were already proved against ink.
- The retention period is still built from `Document::RETENTION`, so changing the
  constant changes the page. Two tests pin that.
- The upload screen had no horizontal-overflow test; the existing one only ever visited
  a document's page. It has one now.

## [0.3.1] - 2026-09-04

### Fixed

- **Encrypted PDFs open.** Documents encrypted with RC4 — the scheme insurers,
  banks and government bodies actually use — were refused as damaged. OpenSSL 3
  keeps RC4 in a legacy provider that is not loaded by default, so the safety
  scanner could not parse them and, being unable to inspect them, refused them.
- **A locked document no longer calls itself broken.** A PDF that needs a
  password it was never given now says so, instead of telling the reader to
  supply an undamaged copy of a file that was never damaged.

### Changed

- A refused document records the parser's own error in the log. The message
  shown to the reader is unchanged — it never names RC4, OpenSSL or Origami —
  but nothing recorded *why* a refusal happened, which is what made this take an
  afternoon to diagnose.

### Notes

- Screening still decrypts before it inspects, so a script hidden inside an
  encrypted document is found and blocked exactly as it was before. Enabling RC4
  does not open a route past the scanner, and a test asserts it.

## [0.3.0] - 2026-09-03

### Changed

- **The upload field is one pill**, matching the chat input: the file control, the
  chosen filename and a "Submit" button on a single line. The browser's own file
  control is replaced rather than restyled — only its button is stylable, and it
  is drawn differently by every browser.
- The heading names the file type: **"Understand any PDF document"**. The app
  accepts nothing else, at the validator and in the field's `accept` attribute.

### Notes

- The field is enhanced by JavaScript, never rendered enhanced. Without
  JavaScript the browser's own control stays, still shows its filename and still
  uploads — a transparent input would show nothing.
- The input is made transparent, not hidden. `opacity-0` keeps its box, which is
  what keeps the browser's `required` check working; collapsing the box makes
  Chrome refuse to submit while reporting it only to the console.

### Security

- **Documents are addressed by an unguessable token, not their id.** Ids were
  sequential, so `/documents/40` and `/documents/41` belonged to different people
  and either could open the other's summary, scan notes and whole conversation.
  The id stays internal — every job still passes it across the queue.

### Added

- **Rate limiting per visitor**: five documents an hour, twenty questions a
  minute. The limiter fails closed, refusing rather than admitting when the
  counter store is unreachable — Rails' own behaviour is the opposite, and would
  switch limiting off exactly when the cache is unwell.

### Fixed

- **`request.remote_ip` is the visitor again.** Render fronts every service with
  Cloudflare, whose ranges Rails does not know, so every request was logged and
  counted as coming from a Cloudflare edge.

### Changed

- Uploads are capped at 8 MB, down from 15 MB, sized for a 512 MB container that
  parses the whole file in the web process.

## [0.2.0] - 2026-09-03

### Changed

- **Documents are now kept for thirty minutes**, not an hour. The period lives in
  `Document::RETENTION` and the reader-facing copy derives from it, so the promise and
  the behaviour cannot drift apart.
- **The retention note counts down** in whole minutes instead of naming a time. It named
  a time in the server's zone, which is nobody's local time: a reader in Los Angeles at
  09:45 was told the document would go at "5:40 PM". A duration is correct everywhere.
  Under a minute it says so in words. Without JavaScript the sentence still states the
  promise and shows no clock.
- **A document leaves the screen when its window closes**, replaced in place by the
  removal message. The replacement ships with the page, so the swap costs no request and
  holds even if the server is asleep. A direct visit to an expired document still
  redirects to the upload screen, unchanged.
- **Questions and answers read as a conversation** — the reader's words on the right, the
  answer on the left, each named in text as "User" or "AI". No avatars and no timestamps;
  a per-message time would reintroduce the same timezone defect the countdown removes.
  Asking now lands on the new answer rather than the top of the page.
- **Progress is reported in pages, not passages.** How a document was chunked is an
  implementation detail; a page belongs to the reader's document. The waiting screen reads
  "Reading page 40 of 138" once both numbers are real, and the ready screen no longer
  counts anything at all.

## [0.1.1] - 2026-09-03

### Changed

- **All tables moved into a dedicated `pdfrag` Postgres schema** so the app can share
  one database with other applications. This covers its own three tables, Active
  Storage's three, and Rails' `schema_migrations` and `ar_internal_metadata` — the two
  that make a shared database dangerous rather than merely crowded. No table was
  renamed, no model changed, and no migration was edited; isolation comes from
  `schema_search_path` in `config/database.yml`.
- `db:ensure_schema` creates the schema, hooked onto `db:migrate` and `db:prepare`.
  A missing schema does not raise in Postgres — `search_path` falls through to
  `public` — so creating it is automatic rather than a documented step.

## [0.1.0] - 2026-09-02

### Added — any-PDF retrieval

Replaces the insurance-specific application on the `mvp` branch.

- **Any PDF**, screened for hostile content before it is stored. Scripts, launch
  actions and attached executables are refused; links and ordinary attachments are
  shown to the reader instead of blocking, because genuine documents are full of both.
- **Retrieval instead of sending the document.** Passages are chunked with overlap,
  embedded into Postgres with pgvector, and only the relevant few are used to summarise
  or answer. Measured on a 140-page policy: 1.7% of the document sent, in two calls.
- **Summaries** built from a generic-anchor query for the passages where a document
  explains itself.
- **Questions** answered from the three nearest passages, with citations to where in
  the document each answer came from. There is no full-text fallback.
- **One-hour retention**, enforced by a column that every read scopes to as well as by
  a deletion job, plus a sweep for orphaned files.

### Changed

- Application renamed from `InsuranceHelper` to `PdfRag`.
- Active Record and Active Storage enabled; the app previously had no database.
- PDF extraction is no longer capped at 20 pages — retrieval replaced the cap.
- A daily API quota is now reported as such rather than as a passing problem.

### Removed

- The insurance-specific session cache, plan screen, and five-minute expiry. All of it
  remains on the `mvp` branch.
