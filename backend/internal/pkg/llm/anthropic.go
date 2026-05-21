// Package llm wraps the small set of LLM operations the wallpaper pipeline
// needs. Right now that is exactly one: vision-based classification of an
// uploaded wallpaper into category + tags + a polished title suggestion.
//
// The wrapper is intentionally narrow — it owns the prompt, the JSON
// schema, the model choice, and the category whitelist. Callers (worker
// hook, autotag CLI, admin handler) just hand it an image URL and get
// back a Classification or an error.
package llm

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log/slog"
	"reflect"
	"strings"

	"github.com/anthropics/anthropic-sdk-go"
	"github.com/anthropics/anthropic-sdk-go/option"
)

// Classification is the structured result of asking Claude to look at a
// wallpaper image: which category bucket it belongs to, a handful of
// search-friendly tags, and (optionally) a cleaner title for SEO when
// the uploaded one is just a stock-photo file ID.
type Classification struct {
	CategorySlug    string   `json:"category_slug"`
	Tags            []string `json:"tags"`
	TitleSuggestion string   `json:"title_suggestion"`
}

// AllowedCategories are the slugs the model is allowed to return. Anything
// outside this set is coerced to "other" before returning to the caller —
// keeps the DB clean regardless of model creativity.
var AllowedCategories = []string{
	"nature", "city", "anime", "abstract", "minimal",
	"tech", "animal", "space", "game", "other",
}

const classifySystemPrompt = `You are a visual classifier for a wallpaper-sharing site. Look at the image and respond with ONLY a JSON object — no markdown fences, no commentary — matching this schema:

{
  "category_slug": one of "nature" | "city" | "anime" | "abstract" | "minimal" | "tech" | "animal" | "space" | "game" | "other",
  "tags": array of 3 to 6 short lowercase English tags. Single words preferred; if a tag needs two words, hyphenate it (e.g. "city-lights"). No spaces inside a tag. Describe visible subject, style, mood, palette.
  "title_suggestion": short descriptive English title, max 60 chars, capturing subject and mood. Empty string if a meaningful title is impossible.
}

Category guidance:
- nature: landscapes, oceans, forests, weather, plants, sunsets
- city: urban scenes, architecture, streets, skylines
- anime: stylized 2D illustrations, manga/anime characters or scenes
- abstract: non-representational patterns, gradients, generative art
- minimal: lots of negative space, single subject, geometric simplicity
- tech: computers, code, circuits, sci-fi tech aesthetics
- animal: animals as the main subject
- space: stars, planets, nebulae, cosmic scenes
- game: video-game screenshots or fan art
- other: anything that fits nowhere else

Pick the single best-fitting category. Return ONLY the JSON object, no preamble, no markdown.`

// Client wraps the Anthropic SDK with the wallpaper-specific Classify call.
type Client struct {
	client   anthropic.Client
	model    anthropic.Model
	enabled  bool
	recorder Recorder
}

// New constructs a Client. Pass an empty apiKey to disable LLM calls — the
// returned client's Classify will always error, which callers (the worker
// hook in particular) interpret as "skip auto-tagging, leave fields blank".
//
// recorder is optional; pass nil to skip per-call usage logging. The
// API server and the CLI tools wire in repo.LLMUsageRepo so every call's
// token count + USD cost lands in the llm_usage table and powers the
// admin dashboard's "LLM 消费" card.
func New(apiKey string, recorder Recorder) *Client {
	c := anthropic.NewClient(option.WithAPIKey(apiKey))
	// Defend against the classic Go gotcha where the caller passes
	// `var r *repo.LLMUsageRepo` (which is nil) into an interface
	// parameter — `recorder == nil` is FALSE there because the
	// interface value carries a non-nil type descriptor. Reflect
	// catches the typed-nil case so we don't NPE in recordUsage.
	if recorder == nil {
		recorder = noopRecorder{}
	} else if v := reflect.ValueOf(recorder); v.Kind() == reflect.Ptr && v.IsNil() {
		recorder = noopRecorder{}
	}
	return &Client{
		client: c,
		// Opus 4.7 is the latest model. For high-volume classification
		// you may want to switch to claude-sonnet-4-6 (3x cheaper) or
		// claude-haiku-4-5 (5x cheaper) — change this constant.
		model:    anthropic.ModelClaudeOpus4_7,
		enabled:  apiKey != "",
		recorder: recorder,
	}
}

// recordUsage extracts token counts from the Anthropic response, computes
// the USD cost from the local pricing table, and writes one row to the
// usage ledger. Logged-only failures — billing accuracy should never
// block a successful LLM result.
func (c *Client) recordUsage(purpose string, usage anthropic.Usage) {
	if c.recorder == nil {
		return
	}
	in := int(usage.InputTokens)
	out := int(usage.OutputTokens)
	cacheRead := int(usage.CacheReadInputTokens)
	cacheCreate := int(usage.CacheCreationInputTokens)
	if err := c.recorder.Record(purpose, string(c.model), in, out, cacheRead, cacheCreate); err != nil {
		// Intentionally noisy on every failure so a missing migration
		// can't silently swallow weeks of accounting.
		slog.Warn("llm: record usage failed", "purpose", purpose, "error", err)
	}
}

// Enabled reports whether an API key was configured at construction time.
// Cheap predicate for callers that want to no-op when LLM features are off.
func (c *Client) Enabled() bool {
	return c != nil && c.enabled
}

// Classify asks Claude to inspect a single wallpaper image (referenced by
// public URL — the model fetches it server-side) and return a structured
// classification. Errors are returned verbatim; callers decide whether to
// retry, skip, or fail the whole batch.
func (c *Client) Classify(ctx context.Context, imageURL string) (*Classification, error) {
	if !c.Enabled() {
		return nil, fmt.Errorf("anthropic api key not configured")
	}

	resp, err := c.client.Messages.New(ctx, anthropic.MessageNewParams{
		Model:     c.model,
		MaxTokens: 512,
		System: []anthropic.TextBlockParam{
			{Text: classifySystemPrompt},
		},
		Messages: []anthropic.MessageParam{
			anthropic.NewUserMessage(
				anthropic.NewImageBlock(anthropic.URLImageSourceParam{URL: imageURL}),
				anthropic.NewTextBlock("Classify this wallpaper image."),
			),
		},
	})
	if err != nil {
		return nil, fmt.Errorf("anthropic api: %w", err)
	}
	c.recordUsage("classify", resp.Usage)

	// First text block in the response is the JSON object. The system
	// prompt asks for no preamble, but defensively trim any markdown
	// fences the model occasionally adds anyway.
	var raw string
	for _, block := range resp.Content {
		if t, ok := block.AsAny().(anthropic.TextBlock); ok {
			raw = strings.TrimSpace(t.Text)
			break
		}
	}
	if raw == "" {
		return nil, fmt.Errorf("anthropic returned no text content")
	}
	raw = strings.TrimPrefix(raw, "```json")
	raw = strings.TrimPrefix(raw, "```")
	raw = strings.TrimSuffix(raw, "```")
	raw = strings.TrimSpace(raw)

	var cls Classification
	if err := json.Unmarshal([]byte(raw), &cls); err != nil {
		return nil, fmt.Errorf("parse classification json: %w (raw=%q)", err, raw)
	}

	// Normalize the category to the known set so we never write a slug
	// the categories table doesn't have a row for.
	if !contains(AllowedCategories, cls.CategorySlug) {
		cls.CategorySlug = "other"
	}
	// Defensive cleanup of the tag list — lowercase, trim, drop empties.
	cleaned := cls.Tags[:0]
	for _, t := range cls.Tags {
		t = strings.ToLower(strings.TrimSpace(t))
		t = strings.ReplaceAll(t, " ", "-")
		if t != "" {
			cleaned = append(cleaned, t)
		}
	}
	cls.Tags = cleaned

	return &cls, nil
}

// QualityAssessment is the moderation hint Claude returns for a single
// wallpaper image. Flag is the bucket (see AllowedQualityFlags); Notes
// is a one-line human-readable reason that goes into wallpapers.quality_notes
// so an admin can scan the queue without re-opening every image.
type QualityAssessment struct {
	Flag  string `json:"flag"`
	Notes string `json:"notes"`
}

// AllowedQualityFlags is the closed vocabulary AssessQuality emits.
// Anything else is coerced to "ok" — better to under-report than to write
// a free-form flag the admin UI doesn't know how to filter on.
var AllowedQualityFlags = []string{
	"ok",
	"blurry",         // out of focus, motion blur, low sharpness
	"watermark",      // visible watermark, photo-stock logo, signature
	"ai_slop",        // obvious AI artifacts (mangled hands, garbled text)
	"text_overlay",   // screenshots, memes, large overlaid text — not wallpaper material
	"low_aesthetic",  // bad composition, heavy noise, blown highlights, dim/dull
}

const assessQualityPrompt = `You are moderating wallpaper uploads on a wallpaper-sharing site. Look at the image and decide whether it is suitable as a desktop or mobile wallpaper. Respond with ONLY a JSON object (no markdown, no commentary):

{
  "flag": one of "ok" | "blurry" | "watermark" | "ai_slop" | "text_overlay" | "low_aesthetic",
  "notes": one short English sentence (≤120 chars) explaining the flag. For "ok", a brief positive note (composition, mood, subject). For non-ok, explain what is wrong concretely.
}

Flag definitions (be conservative — when uncertain, prefer "ok"):
- ok: A reasonable wallpaper. Sharp enough at viewing distance, no overlay text, no watermark, no clear AI artifacts, decent composition.
- blurry: Out of focus, motion blur, or so soft that the main subject lacks definition. Intentional shallow depth-of-field with a sharp subject is NOT blurry.
- watermark: A visible photographer logo, stock-site watermark, signature, or printed URL that the user would want removed.
- ai_slop: Obvious AI-generation artifacts — mangled hands, garbled text, melted faces, impossible anatomy. Stylized AI illustrations without such defects are NOT ai_slop.
- text_overlay: Screenshots, memes, posters, or images with prominent overlaid text that dominate the frame. A small caption or signature corner does not count.
- low_aesthetic: Wallpaper-unfriendly — heavy compression noise, blown-out highlights, very dim/dull subject filling the frame, casual snapshot quality.

Return ONLY the JSON object.`

// AssessQuality asks Claude to look at one wallpaper image and return a
// moderation flag + a short notes line. Errors and unknown flags coerce
// to "ok" — failing safe so a hiccup in the assessor doesn't flag good
// content. Caller is responsible for storing the result.
func (c *Client) AssessQuality(ctx context.Context, imageURL string) (*QualityAssessment, error) {
	if !c.Enabled() {
		return nil, fmt.Errorf("anthropic api key not configured")
	}

	resp, err := c.client.Messages.New(ctx, anthropic.MessageNewParams{
		Model:     c.model,
		MaxTokens: 200,
		System: []anthropic.TextBlockParam{
			{Text: assessQualityPrompt},
		},
		Messages: []anthropic.MessageParam{
			anthropic.NewUserMessage(
				anthropic.NewImageBlock(anthropic.URLImageSourceParam{URL: imageURL}),
				anthropic.NewTextBlock("Assess this wallpaper."),
			),
		},
	})
	if err != nil {
		return nil, fmt.Errorf("anthropic api: %w", err)
	}
	c.recordUsage("quality", resp.Usage)

	var raw string
	for _, block := range resp.Content {
		if t, ok := block.AsAny().(anthropic.TextBlock); ok {
			raw = strings.TrimSpace(t.Text)
			break
		}
	}
	if raw == "" {
		return nil, fmt.Errorf("anthropic returned no text content")
	}
	raw = strings.TrimPrefix(raw, "```json")
	raw = strings.TrimPrefix(raw, "```")
	raw = strings.TrimSuffix(raw, "```")
	raw = strings.TrimSpace(raw)

	var q QualityAssessment
	if err := json.Unmarshal([]byte(raw), &q); err != nil {
		return nil, fmt.Errorf("parse quality json: %w (raw=%q)", err, raw)
	}
	q.Flag = strings.ToLower(strings.TrimSpace(q.Flag))
	if !contains(AllowedQualityFlags, q.Flag) {
		q.Flag = "ok"
	}
	q.Notes = strings.TrimSpace(q.Notes)
	if len(q.Notes) > 240 {
		q.Notes = q.Notes[:240]
	}
	return &q, nil
}

// TagInput is one row of the tag inventory fed into ProposeTagMerges. The
// count is the number of wallpapers currently linked to the tag — Claude
// uses it to pick which name in a synonym set becomes canonical (heaviest
// wins).
type TagInput struct {
	Name  string
	Count int
}

// TagMerge says "rewrite every link from `From` to `To`, then drop `From`."
// From and To always differ. Tags that should stay as-is don't appear here.
type TagMerge struct {
	From string `json:"from"`
	To   string `json:"to"`
}

const proposeTagMergesPrompt = `You are cleaning up a tag taxonomy for a wallpaper-sharing site. Below is the full inventory of tags and how many wallpapers carry each. Return ONLY a JSON object (no markdown, no commentary):

{
  "renames": [{"from": "old-tag", "to": "canonical-tag"}, ...]
}

Rules:
- Merge singular/plural variants (e.g. "mountain" + "mountains" → keep the more common form; usually the plural for countable things like mountains, trees, clouds; singular for mass nouns like fog, snow).
- Merge spelling/separator variants ("blackandwhite" or "black_and_white" → "black-and-white"; "ai art" or "aiart" → "ai-art").
- Merge clear typos and obvious synonyms ("skyscraper" + "skyscrapers" → "skyscrapers"; "monochrome" + "black-and-white" → "black-and-white" if both meaningfully overlap).
- Be conservative on near-synonyms with distinct nuance. "city" vs "urban" vs "cityscape" — do NOT merge; they capture different things. "ocean" vs "sea" — do NOT merge. "minimal" vs "minimalist" — DO merge.
- Lowercase only; words joined by hyphens, not spaces or underscores.
- The "to" target may be either an existing tag or a new normalized form. Pick the form with the higher count when in doubt.
- Output only renames where "from" != "to".

Tags (one per line, "name | count", sorted by count desc):
%s`

// ProposeTagMerges asks Claude to look at the full tag inventory and
// suggest a set of from→to renames that consolidate trivial variants
// (singular/plural, hyphenation, typos, obvious synonyms). It does NOT
// apply anything — the caller is expected to surface the proposals for
// review and then run them through the merge SQL itself.
func (c *Client) ProposeTagMerges(ctx context.Context, tags []TagInput) ([]TagMerge, error) {
	if !c.Enabled() {
		return nil, fmt.Errorf("anthropic api key not configured")
	}
	var b strings.Builder
	for _, t := range tags {
		fmt.Fprintf(&b, "%s | %d\n", t.Name, t.Count)
	}

	resp, err := c.client.Messages.New(ctx, anthropic.MessageNewParams{
		Model:     c.model,
		MaxTokens: 8000,
		System: []anthropic.TextBlockParam{
			{Text: fmt.Sprintf(proposeTagMergesPrompt, b.String())},
		},
		Messages: []anthropic.MessageParam{
			anthropic.NewUserMessage(anthropic.NewTextBlock("Output the JSON now.")),
		},
	})
	if err != nil {
		return nil, fmt.Errorf("anthropic api: %w", err)
	}
	c.recordUsage("tag_merge", resp.Usage)

	var raw string
	for _, block := range resp.Content {
		if t, ok := block.AsAny().(anthropic.TextBlock); ok {
			raw = strings.TrimSpace(t.Text)
			break
		}
	}
	if raw == "" {
		return nil, fmt.Errorf("anthropic returned no text content")
	}
	raw = strings.TrimPrefix(raw, "```json")
	raw = strings.TrimPrefix(raw, "```")
	raw = strings.TrimSuffix(raw, "```")
	raw = strings.TrimSpace(raw)

	var out struct {
		Renames []TagMerge `json:"renames"`
	}
	if err := json.Unmarshal([]byte(raw), &out); err != nil {
		return nil, fmt.Errorf("parse renames json: %w (first 300 chars: %q)", err, truncateLLM(raw, 300))
	}
	// Defensive: drop self-renames and empty entries.
	cleaned := out.Renames[:0]
	for _, m := range out.Renames {
		from := strings.ToLower(strings.TrimSpace(m.From))
		to := strings.ToLower(strings.TrimSpace(m.To))
		if from == "" || to == "" || from == to {
			continue
		}
		cleaned = append(cleaned, TagMerge{From: from, To: to})
	}
	return cleaned, nil
}

// ThemeCandidate is one wallpaper handed to ProposeWeeklyTheme — the
// model sees the id, the existing tags/category, and the dominant
// color so it can group by any combination of those dimensions.
type ThemeCandidate struct {
	ID         int64    `json:"id"`
	CategoryID int64    `json:"category_id"`
	Category   string   `json:"category"`
	Tags       []string `json:"tags"`
	Title      string   `json:"title"`
	Dominant   string   `json:"dominant"`
}

// ThemePick is the LLM's answer for a weekly theme collection: a
// human-readable theme name (used as the collection title), a short
// description, and the 10 wallpaper IDs that should belong to it. The
// caller validates that the IDs are a subset of what was offered.
type ThemePick struct {
	ThemeName    string  `json:"theme_name"`
	Description  string  `json:"description"`
	WallpaperIDs []int64 `json:"wallpaper_ids"`
}

const proposeWeeklyThemePrompt = `You are an editor curating a weekly themed wallpaper collection. From the catalog below, pick a SINGLE coherent theme and the 10 wallpapers that best embody it.

The theme can be:
- a SUBJECT (e.g. "Sunsets at the Horizon", "Quiet Mountain Mornings", "Neon Cyberpunk Streets")
- a MOOD (e.g. "Dreamy Pastels", "Moody and Atmospheric", "Bold and Vibrant")
- a STYLE (e.g. "Minimal Geometry", "Film Photography Aesthetic")
- a DEVICE FIT (e.g. "Made for Mac Studio Displays" when the candidates share a portrait/ultrawide aspect)

Rules:
- The 10 wallpapers MUST be genuinely related to the theme. Better to have 7 strong picks than 10 loose ones.
- If no clean theme exists for at least 6 wallpapers, return an empty wallpaper_ids array; the caller will skip generation this week.
- The theme name should be short (≤50 chars), evocative, and Title Case.
- Description is one sentence (≤140 chars) elaborating the theme — what unites these picks.
- Output ONLY a JSON object — no markdown fence, no commentary:

{
  "theme_name": "...",
  "description": "...",
  "wallpaper_ids": [123, 456, ...]
}

Catalog (JSON array, one row per wallpaper):
%s`

// ProposeWeeklyTheme asks Claude to scan a candidate pool and propose
// one coherent theme with 10 wallpapers that fit it. The caller
// validates that wallpaper_ids ⊆ candidates and that there are at
// least min_count of them; a "no clean theme this week" verdict comes
// back as an empty wallpaper_ids slice.
func (c *Client) ProposeWeeklyTheme(ctx context.Context, candidates []ThemeCandidate) (*ThemePick, error) {
	if !c.Enabled() {
		return nil, fmt.Errorf("anthropic api key not configured")
	}
	catalog, err := json.Marshal(candidates)
	if err != nil {
		return nil, fmt.Errorf("marshal catalog: %w", err)
	}
	resp, err := c.client.Messages.New(ctx, anthropic.MessageNewParams{
		Model:     c.model,
		MaxTokens: 1500,
		System: []anthropic.TextBlockParam{
			{Text: fmt.Sprintf(proposeWeeklyThemePrompt, string(catalog))},
		},
		Messages: []anthropic.MessageParam{
			anthropic.NewUserMessage(anthropic.NewTextBlock("Output the JSON now.")),
		},
	})
	if err != nil {
		return nil, fmt.Errorf("anthropic api: %w", err)
	}
	c.recordUsage("weekly_theme", resp.Usage)
	var raw string
	for _, block := range resp.Content {
		if t, ok := block.AsAny().(anthropic.TextBlock); ok {
			raw = strings.TrimSpace(t.Text)
			break
		}
	}
	if raw == "" {
		return nil, fmt.Errorf("anthropic returned no text content")
	}
	raw = strings.TrimPrefix(raw, "```json")
	raw = strings.TrimPrefix(raw, "```")
	raw = strings.TrimSuffix(raw, "```")
	raw = strings.TrimSpace(raw)
	var out ThemePick
	if err := json.Unmarshal([]byte(raw), &out); err != nil {
		return nil, fmt.Errorf("parse theme json: %w (first 300 chars: %q)", err, truncateLLM(raw, 300))
	}
	out.ThemeName = strings.TrimSpace(out.ThemeName)
	out.Description = strings.TrimSpace(out.Description)
	return &out, nil
}

func truncateLLM(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}

func contains(list []string, s string) bool {
	for _, v := range list {
		if v == s {
			return true
		}
	}
	return false
}

// ExpandWallpaperPrompt turns a vague user idea (often Chinese, often
// just a noun phrase) into a richer English image-generation prompt for
// gpt-image-2. The wallpaper-specific composition + safety constraints
// are appended by the caller (cmd/aigen), not by the LLM — keeping the
// rules visible in code rather than buried in a system prompt the user
// can't see.
func (c *Client) ExpandWallpaperPrompt(ctx context.Context, idea string) (string, error) {
	if !c.Enabled() {
		return "", fmt.Errorf("anthropic api key not configured")
	}
	resp, err := c.client.Messages.New(ctx, anthropic.MessageNewParams{
		Model: c.model,
		// Production-grade prompts (130-220 words + named engine + palette
		// + materials + lighting + atmosphere + quality markers) routinely
		// run 400-700 output tokens — keep plenty of headroom so Claude's
		// reply doesn't get truncated mid-sentence.
		MaxTokens: 1200,
		System: []anthropic.TextBlockParam{
			{Text: expandPromptSystem},
		},
		Messages: []anthropic.MessageParam{
			anthropic.NewUserMessage(anthropic.NewTextBlock(idea)),
		},
	})
	if err != nil {
		return "", fmt.Errorf("anthropic: %w", err)
	}
	c.recordUsage("prompt_expand", resp.Usage)

	for _, block := range resp.Content {
		if t, ok := block.AsAny().(anthropic.TextBlock); ok {
			out := strings.TrimSpace(t.Text)
			// Strip wrapping quotes a model sometimes adds despite the
			// system prompt asking for none.
			out = strings.Trim(out, `"'`)
			return out, nil
		}
	}
	return "", fmt.Errorf("anthropic: empty response")
}

const expandPromptSystem = `You expand a brief idea into a production-grade prompt for OpenAI gpt-image-2, intended for 4K desktop wallpapers that reward extended viewing. Your output is handed to the image model after a small composition+safety suffix is appended — so every sensory register the renderer needs to commit to has to be in YOUR text.

The user gives a short idea (often Chinese, sometimes a single noun phrase). You output ONE English prompt with:

1. **A specific stylistic anchor** — pair "photorealistic" only with an INSTITUTIONAL / GENRE / SOFTWARE reference, NEVER a named individual person or copyrighted film/show title. Safe references include:
   - **Institutions**: "National Geographic photography style", "Vogue editorial", "BBC nature documentary cinematography"
   - **Movements**: "sumi-e ink wash", "ukiyo-e woodblock", "Art Nouveau botanical", "Bauhaus geometric", "Scandinavian minimalist", "Japanese architectural editorial"
   - **Genres**: "anime aesthetic", "matte painting concept art", "deep-ocean cinematography", "macro nature photography", "tilt-shift miniature photography", "isometric low-poly vector"
   - **Software / Engines**: "Octane Render product visualization", "Unreal Engine 5 volumetric concept art", "iridescent fluid-simulation render"
   - **Eras**: "1960s mid-century graphic design", "late-19th-century lithograph"
   FORBIDDEN: real living photographers, directors, artists (e.g. Makoto Shinkai, Roger Deakins, Annie Leibovitz, Beeple, Hiroshi Sugimoto, Caleb Charland, Beksiński, James Cameron) and copyrighted titles (e.g. Blade Runner, Studio Ghibli films, anime titles) — these trip OpenAI's safety filter and the prompt gets rejected. NEVER let "photorealistic" or "ultra-realistic" stand alone without a non-personal stylistic anchor.

2. **Element-level specificity — NEVER abstract** — every noun in the prompt must be a SPECIFIC NAMED THING with at least one distinguishing property, not a generic category. Don't write "a mountain"; write "a sharp granite spire crowned with a single illuminated observatory dome on its eastern shoulder, ringed by ribbons of cyclonic alpine cumulus catching low golden light". Don't write "a forest"; write "a stand of bioluminescent silver-birch with cyan capillary veins glowing through translucent bark, ferns at their roots fluorescing in mint and rose". Build the scene as a chain of concrete, fully-realized elements — each with its OWN material, weather, lighting, and color attached.

3. **Bright, vivid, saturated default palette** — wallpapers should feel optimistic and alive. Default to radiant noon, golden-hour, vivid sunset, candy-bright sci-fi, sunlit pastels, electric neon-against-light-blue, prismatic full-spectrum. AVOID ink-black, midnight, void, dark-grey-on-dark as the dominant ground colour unless the user idea specifically says "night", "dusk", "abyss", or similar. Even "night sky" scenes should have something luminous claiming most of the frame (auroras, glowing structures, magenta star clouds, vivid neon). Use 3-5 named colours with material qualifier ("electric coral, sunlit champagne, fresh mint green, cobalt sky, soft lavender mist") — every named colour should be vivid enough to read clearly.

4. **All FIVE sensory registers (in addition to the above)**:
   - **Light**: direction, angle, quality, color temperature ("low golden raking light from camera-left at 30°, cool cyan rim glow from behind, soft bounce fill from below"). Prefer warm or vivid lighting; high-key over low-key.
   - **Materials**: substances at micro-detail level ("brushed titanium with anisotropic specular streaks", "matte unglazed porcelain with hairline kintsugi gold veins")
   - **Atmosphere**: particulates, volumetrics, refraction ("ground-hugging mist with visible dust motes catching slanted sun, atmospheric perspective fading distant elements to 6% haze")
   - **Depth**: explicit foreground / midground / background separation ("crisp foreground at f/2.8 sharp focus, midground gentle defocus, background dissolved into bokeh")

5. **Desktop-wallpaper composition** — wallpapers are NOT posters. The user puts icons on top. Include:
   - "Wide-angle composition" (or "ultrawide cinematic framing")
   - "Clean negative space in the upper-left quadrant and across the bottom third of the frame" so desktop icons don't fight the subject
   - "Minimalist center-of-interest with breathing room"
   - Subject lives in the lower-right or center-right ⅔; left third + top third stay simpler
   - 25% safety margin from every edge for crop-to-mobile

6. **Literary subject + active verb, not a feature list** — the difference between a flat prompt and one that produces a striking image is a subject doing something. "A giant luminescent octopus **glides** through a pitch-black trench, its tendrils **unfurling** into galaxy dust" reads as alive; "an octopus with tendrils that look like stars" reads as a flashcard. Pick a verb (drifts, ripples, blooms, ignites, shatters, exhales, crystallizes, dissolves into …). Pair it with a single surreal twist that turns the ordinary into the impossible.

7. **Compound material+form atoms** — instead of long adjective chains, build the scene from 3-5 "material+shape" units stacked in one sentence. Pattern: "[surface qualifier]-[material] [geometry]". E.g. "velvet-finish cylinder, liquid mercury dodecahedron, smoked obsidian pyramid, raw sandstone disc". These compounds give the renderer precise geometry + finish in one breath.

8. **Counter-modifiers against AI-slop** — interleave "subtle", "honest", "refined", "restrained", "authentic", "shippable not concept-art" with the maximalist quality keywords. Too much "epic / dramatic / ultimate" reads as cheap. The strongest GPT-Image-2 prompts feel grounded.

9. **PBR / VFX vocabulary the model recognises** — sprinkle: "physically based materials", "subtle contact AO", "soft HDRI fill light", "anisotropic specular streaks", "subsurface scattering", "ray-traced caustics", "refined contact shadow", "pixel-crisp focal point", "shallow DOF with parallaxed background".

10. **Quality stack at the end** — close with: "Octane Render production quality, 8K UHD textures, cinematic color grading, ray-traced specular highlights, subsurface scattering where applicable, editorial production-grade rendering, ultra-sharp focus on the focal subject, intricate fine detail at every viewing distance".

11. **NEVER asks for**: people, faces, text, words, captions, signage, logos, brand names, watermarks, recognizable real-world landmarks. Avoid AI-slop tells: "smooth", "perfect", "flawless" alone.

Output ONLY the prompt text. No quotes, no preamble, no explanation. 4-7 sentences, 130-220 words. Lean LONG and specific.

---
REFERENCE EXAMPLES (study the structure; do NOT copy verbatim, do NOT cite real people):

NATURE / honest realism: "A wide-angle landscape of a serene misty mountain lake at sunrise. Mist drifts low over the water, the surface mirroring a pine ridge in a quiet honey-gold light. Honest National Geographic photography style — subtle, restrained, no over-saturation. Composition leaves the upper-left third of the sky calm and uncluttered for desktop icons; the focal pines anchor the lower-right two-thirds."

SCI-FI / Unreal-Engine concept: "A futuristic cyberpunk skyline ignites at night; rain hisses through canyons of neon while flying vehicles trace pink-and-cyan arcs between rain-slicked towers. Unreal Engine 5 volumetric render, refined contact shadows, ray-traced reflections on wet pavement. Tall spires push into the right two-thirds; the upper-left holds a darker negative-space sky for icon placement."

SURREAL / literary subject + active verb: "A giant luminescent octopus glides through a pitch-black trench, its tendrils unfurling into galaxy dust and constellations that hang in the cold water like a slow-moving aurora. Deep midnight blue dissolving into violet, phosphorescent teal accents. Deep-ocean documentary cinematography crossed with surreal matte-painting concept art — subtle contact AO around each suction cup, physically based materials with subsurface scattering on the translucent skin. Honest restrained tonalism — shippable, not bombast. Subject drifts into the lower-right; the upper-left water remains a quiet ink-black field for desktop icons."

MATERIAL / compound-atom: "A precisely arranged still life floats in soft single-HDRI light: velvet-finish indigo cylinder, liquid mercury dodecahedron, smoked obsidian pyramid, raw sandstone disc, translucent nacre torus. Bauhaus geometric editorial aesthetic, subtle contact AO, refined contact shadow, anisotropic specular on the metal, pixel-crisp focal sharpness with parallaxed background defocus. Composition centered with breathing room — the upper-left and bottom third stay an unbroken matte gradient for icon space."`

// ─────────────────────────────────────────────────────────────────────
// Collection mode: vision-driven prompt variation
// ─────────────────────────────────────────────────────────────────────

// CollectionVariants returns N prompt variants that collectively form a
// thematic collection visually grounded in the reference image. Claude
// looks at the reference (passed as raw image bytes + MIME type) to
// internalise the style — palette, lighting, materials, mood — then
// generates N distinct compositional variations all in that style.
//
// Each output prompt follows the same rules as ExpandWallpaperPrompt
// (detailed, bright, icon-safe composition, gpt-image-2 ready).
func (c *Client) CollectionVariants(ctx context.Context, refImage []byte, refMediaType string, count int, hint string) ([]string, error) {
	if !c.Enabled() {
		return nil, fmt.Errorf("anthropic api key not configured")
	}
	if count < 1 || count > 20 {
		return nil, fmt.Errorf("count must be 1..20, got %d", count)
	}

	hintLine := ""
	if hint = strings.TrimSpace(hint); hint != "" {
		hintLine = "\n\nOptional user hint: " + hint
	}

	userText := fmt.Sprintf(
		"Study the reference image's style — palette, lighting, materials, mood, render aesthetic. "+
			"Then produce %d distinct prompt variants that ALL feel like they belong in one collection with the reference, "+
			"but differ in subject / composition / specific scene so the resulting wallpapers are visually varied "+
			"rather than near-duplicates. Each variant is a standalone image-generation prompt, NOT a description of the reference.%s",
		count, hintLine,
	)

	resp, err := c.client.Messages.New(ctx, anthropic.MessageNewParams{
		Model:     c.model,
		MaxTokens: 3500,
		System: []anthropic.TextBlockParam{
			{Text: collectionVariantsSystem},
		},
		Messages: []anthropic.MessageParam{
			anthropic.NewUserMessage(
				anthropic.NewImageBlock(anthropic.Base64ImageSourceParam{
					MediaType: anthropic.Base64ImageSourceMediaType(refMediaType),
					Data:      base64.StdEncoding.EncodeToString(refImage),
				}),
				anthropic.NewTextBlock(userText),
			),
		},
	})
	if err != nil {
		return nil, fmt.Errorf("anthropic api: %w", err)
	}
	c.recordUsage("collection_variants", resp.Usage)

	var raw string
	for _, block := range resp.Content {
		if t, ok := block.AsAny().(anthropic.TextBlock); ok {
			raw = strings.TrimSpace(t.Text)
			break
		}
	}
	if raw == "" {
		return nil, fmt.Errorf("anthropic returned no text content")
	}
	raw = strings.TrimPrefix(raw, "```json")
	raw = strings.TrimPrefix(raw, "```")
	raw = strings.TrimSuffix(raw, "```")
	raw = strings.TrimSpace(raw)

	var doc struct {
		Variants []string `json:"variants"`
	}
	if err := json.Unmarshal([]byte(raw), &doc); err != nil {
		return nil, fmt.Errorf("parse variants json: %w (raw=%q)", err, truncateLLM(raw, 200))
	}
	if len(doc.Variants) == 0 {
		return nil, fmt.Errorf("anthropic returned 0 variants")
	}
	// Trim each one in case the model wrapped them in quotes.
	for i := range doc.Variants {
		doc.Variants[i] = strings.Trim(strings.TrimSpace(doc.Variants[i]), `"'`)
	}
	return doc.Variants, nil
}

const collectionVariantsSystem = `You are building a wallpaper collection grounded in a visual reference. The user gives you a single reference image and asks for N variation prompts. Your job:

1. INTERNALISE the reference's style — its dominant palette, lighting register, materials, render aesthetic (photographic / matte-painting / 3D render / illustration), mood, and any signature visual motifs. DO NOT just describe the reference back; the goal is to capture the *style fingerprint* that the variants will share.

2. PRODUCE N image-generation prompts that all feel like siblings of the reference but explore DIFFERENT subjects / compositions / scenes. The collection should feel curated, not redundant. Variants should differ in: focal subject, time of day or lighting moment, camera framing, dominant element. They should share: overall palette family, render aesthetic, atmospheric quality, mood, level of fidelity.

3. EVERY variant follows these rules (same as our solo prompt expander):
   - **Stylistic anchor**: institutional / genre / software reference (e.g. "National Geographic photography", "Unreal Engine 5 volumetric concept art", "sumi-e ink wash", "isometric low-poly vector"). NEVER name a real living photographer, director, artist (e.g. Makoto Shinkai, Roger Deakins, Beeple) or copyrighted film title (Blade Runner, Studio Ghibli films). These trip OpenAI's safety filter.
   - **Element-level specificity**: every noun is a specific named thing with at least one distinguishing property. Not "a city"; "a coral-and-glass spiral arcology rising from a turquoise lagoon, rooftop gardens cascading in tiered hexagons".
   - **Bright, vivid, saturated palette** by default (unless the reference is clearly dark / nocturnal — in that case match the reference). Use 3-5 named colours.
   - **5 sensory registers**: light (direction/angle/quality), materials (micro-detail), atmosphere (particulates/volumetrics), depth (foreground/midground/background), palette (named colours).
   - **Desktop-wallpaper composition**: subject in lower-right or center-right ⅔; clean negative space in upper-left quadrant and across bottom third for desktop icons; 25% safety margin all edges.
   - **Literary subject + active verb**: subjects drift / bloom / ignite / cascade / unfurl / dissolve into …
   - **Compound material+form atoms**: 3-5 "[surface]-[material] [geometry]" units in one sentence.
   - **Counter-modifiers**: weave in "honest", "restrained", "shippable not concept-art" against the maximalist quality keywords.
   - **PBR vocabulary**: "physically based materials", "subtle contact AO", "ray-traced caustics", "subsurface scattering", "anisotropic specular", "pixel-crisp focal point".
   - **Quality stack**: close every variant with "Octane Render production quality, 8K UHD textures, cinematic color grading, ray-traced specular highlights, subsurface scattering where applicable, editorial production-grade rendering, ultra-sharp focus on the focal subject, intricate fine detail at every viewing distance".
   - **NEVER**: people, faces, text, words, captions, signage, logos, brand names, watermarks, recognizable real-world landmarks, "smooth" / "perfect" / "flawless" alone.

4. Each variant is 130-220 words, 4-7 sentences, lean LONG and specific.

OUTPUT FORMAT: a single JSON object, NO markdown fences, NO preamble, exactly this shape:

{"variants": ["prompt 1 …", "prompt 2 …", "prompt 3 …"]}

Each array entry is the full standalone prompt for one variant. NOTHING ELSE.`
