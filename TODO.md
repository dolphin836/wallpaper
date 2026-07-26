# TODO

Outstanding work tracked separately from the issue tracker — usually
because it's a "we discussed this and decided to defer" item rather
than a bug or scoped feature.

## Search

### Natural-language wallpaper search (deferred 2026-05-20)

A site-wide search bar in the top nav that interprets free-form
queries (e.g. *"a calm sunset over mountains"*, *"moody dark
cityscape"*, *"minimal pastel"*) and returns the most relevant
wallpapers — not a literal substring match on title/tag.

**Two implementation tiers, deferred for now:**

- **L1 — LLM query decomposition.** A small Claude call parses the
  query into `{category, tags[], color_hints[], mood}` and the
  backend ranks candidates by tag-hit count + category match. About
  half a day of work; ~$0.005 per query; ~60% accuracy on
  object/mood queries.
- **L2 — Embedding-based semantic search.** Compute per-wallpaper
  embeddings (Voyage or OpenAI; Anthropic has no embedding
  endpoint), store in `pgvector`, ANN-search per query.
  About 1.5 days of work; one-time ~$0.05 for the current corpus,
  ~$0.0001 per query. Handles vibes-based queries that L1 misses
  ("dreamy", "retro", "cyberpunk neon").

**Plan when we pick this back up:**

1. Ship the top-nav search input + `/search?q=...` route reusing the
   HomePage gallery for results.
2. Wire L1 first. Run for a few weeks.
3. Inspect query logs — if a meaningful share of queries are
   vibes-based and L1 visibly fumbles them, upgrade to L2.

Trigger to revisit: search log volume justifies the work, or a
specific UX request for vibes-based queries.

## Product backlog

### Discovery and detail navigation (recorded 2026-07-25)

- Add color and resolution filters to Discover.
- Add previous/next wallpaper navigation to the detail page.

### macOS client (recorded 2026-07-25)

- Support applying wallpapers to the Lock Screen.
- Support dynamic particle-effect wallpapers.
  - Phase 1 implemented on `codex/generative-wallpapers`: Metal-rendered Starfield, Rain, Campfire, and Fireflies presets with live catalogue/detail previews, display targeting, background persistence, and relaunch restoration.
