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

// AIGenerationAssessment is a deliberately conservative judgement about
// whether an image was generated by an AI model. Confidence is normalized to
// 0..1; callers can choose the threshold at which they persist the flag.
type AIGenerationAssessment struct {
	IsAIGenerated bool    `json:"is_ai_generated"`
	Confidence    float64 `json:"confidence"`
	Notes         string  `json:"notes"`
}

const assessAIGenerationPrompt = `You are reviewing wallpapers to identify images that were clearly generated by an AI image model. Respond with ONLY a JSON object (no markdown, no commentary):

{
  "is_ai_generated": boolean,
  "confidence": number from 0 to 1,
  "notes": one short English sentence (max 140 chars) naming the strongest visible evidence
}

Be conservative. Mark true only when the image itself contains strong, visible evidence of AI generation: malformed anatomy or objects, incoherent fine detail, melted or repeated textures, garbled pseudo-text, impossible reflections or geometry, inconsistent lighting, or a highly characteristic synthetic rendering pattern with multiple supporting clues.

Do NOT mark true merely because an image is an illustration, 3D render, abstract/generative artwork, heavily edited photo, anime art, or unusually polished. Those can be human-made. If the evidence is ambiguous, return false and a confidence below 0.85. Do not use metadata or provenance; judge only the pixels.

Return ONLY the JSON object.`

// AssessAIGenerated inspects raw preview-image bytes. Unlike Classify and
// AssessQuality it intentionally does not accept a URL: the batch task must
// download preview_url itself, making it impossible for this path to fall back
// to an original image and waste bandwidth.
func (c *Client) AssessAIGenerated(ctx context.Context, image []byte, mediaType string) (*AIGenerationAssessment, error) {
	if !c.Enabled() {
		return nil, fmt.Errorf("anthropic api key not configured")
	}
	if len(image) == 0 {
		return nil, fmt.Errorf("preview image is empty")
	}
	switch mediaType {
	case "image/jpeg", "image/png", "image/gif", "image/webp":
	default:
		return nil, fmt.Errorf("unsupported preview media type %q", mediaType)
	}

	resp, err := c.client.Messages.New(ctx, anthropic.MessageNewParams{
		Model:     c.model,
		MaxTokens: 220,
		System: []anthropic.TextBlockParam{
			{Text: assessAIGenerationPrompt},
		},
		Messages: []anthropic.MessageParam{
			anthropic.NewUserMessage(
				anthropic.NewImageBlock(anthropic.Base64ImageSourceParam{
					MediaType: anthropic.Base64ImageSourceMediaType(mediaType),
					Data:      base64.StdEncoding.EncodeToString(image),
				}),
				anthropic.NewTextBlock("Determine whether this preview was clearly AI-generated."),
			),
		},
	})
	if err != nil {
		return nil, fmt.Errorf("anthropic api: %w", err)
	}
	c.recordUsage("ai_detection", resp.Usage)

	var raw string
	for _, block := range resp.Content {
		if t, ok := block.AsAny().(anthropic.TextBlock); ok {
			raw = t.Text
			break
		}
	}
	return parseAIGenerationAssessment(raw)
}

func parseAIGenerationAssessment(raw string) (*AIGenerationAssessment, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil, fmt.Errorf("anthropic returned no text content")
	}
	raw = strings.TrimPrefix(raw, "```json")
	raw = strings.TrimPrefix(raw, "```")
	raw = strings.TrimSuffix(raw, "```")
	raw = strings.TrimSpace(raw)

	var assessment AIGenerationAssessment
	if err := json.Unmarshal([]byte(raw), &assessment); err != nil {
		return nil, fmt.Errorf("parse ai detection json: %w (raw=%q)", err, truncateLLM(raw, 240))
	}
	if assessment.Confidence < 0 {
		assessment.Confidence = 0
	}
	if assessment.Confidence > 1 {
		assessment.Confidence = 1
	}
	assessment.Notes = strings.TrimSpace(assessment.Notes)
	if len(assessment.Notes) > 280 {
		assessment.Notes = assessment.Notes[:280]
	}
	return &assessment, nil
}

// AllowedQualityFlags is the closed vocabulary AssessQuality emits.
// Anything else is coerced to "ok" — better to under-report than to write
// a free-form flag the admin UI doesn't know how to filter on.
var AllowedQualityFlags = []string{
	"ok",
	"blurry",        // out of focus, motion blur, low sharpness
	"watermark",     // visible watermark, photo-stock logo, signature
	"ai_slop",       // obvious AI artifacts (mangled hands, garbled text)
	"text_overlay",  // screenshots, memes, large overlaid text — not wallpaper material
	"low_aesthetic", // bad composition, heavy noise, blown highlights, dim/dull
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

// ProposeThemeAccent asks Claude to pick a single OKLCH accent color
// for an existing themed collection given its title + description.
// Used by cmd/recolor-themes to backfill older collections that do
// not yet have accent colors.
func (c *Client) ProposeThemeAccent(ctx context.Context, title, description string) (string, error) {
	if !c.Enabled() {
		return "", fmt.Errorf("anthropic api key not configured")
	}
	system := `You are picking a single OKLCH accent color for a wallpaper collection theme.

Output ONE color: oklch(L C H) where
  L = 0.55–0.75 (mid-bright, legible on light paper)
  C = 0.10–0.20 (saturated but not garish)
  H = 0–360

The hue should evoke the theme's mood without being literal — a winter theme doesn't have to be blue, but should feel cool; a desert theme doesn't have to be tan, but should feel warm.

Output ONLY the oklch() string. No fence, no commentary, no explanation.

Examples:
  Theme: "Sunset Silhouettes"           → oklch(0.65 0.18 35)
  Theme: "Snowbound Stillness"          → oklch(0.70 0.06 230)
  Theme: "Neon Cyberpunk Streets"       → oklch(0.60 0.18 290)
  Theme: "Cats in Curious Moments"      → oklch(0.65 0.13 55)
  Theme: "Mirror Lakes"                 → oklch(0.62 0.10 200)`

	resp, err := c.client.Messages.New(ctx, anthropic.MessageNewParams{
		Model:     c.model,
		MaxTokens: 80,
		System:    []anthropic.TextBlockParam{{Text: system}},
		Messages: []anthropic.MessageParam{
			anthropic.NewUserMessage(anthropic.NewTextBlock(fmt.Sprintf("Title: %q\nDescription: %q", title, description))),
		},
	})
	if err != nil {
		return "", fmt.Errorf("anthropic api: %w", err)
	}
	c.recordUsage("theme_accent", resp.Usage)
	for _, block := range resp.Content {
		if t, ok := block.AsAny().(anthropic.TextBlock); ok {
			raw := strings.TrimSpace(t.Text)
			raw = strings.Trim(raw, "`\"' \n")
			if !strings.HasPrefix(raw, "oklch(") {
				return "", fmt.Errorf("malformed accent: %q", truncateLLM(raw, 100))
			}
			return raw, nil
		}
	}
	return "", fmt.Errorf("anthropic returned no text")
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

const expandPromptSystem = `You expand a brief idea (often Chinese, sometimes one noun) into ONE production prompt for OpenAI gpt-image-2, intended for a 4K desktop wallpaper. Output English, prompt only — no preamble, no quotes, no commentary.

═══════════════════════════════════════════════════════════════════
WHY THIS PROMPT EXISTS (READ FIRST)
═══════════════════════════════════════════════════════════════════

The single biggest determinant of output quality is choosing the RIGHT WORD-PACK for the subject category. The "Octane Render + 8K UHD + subsurface scattering + ray-traced + PBR" word stack works for digital concept art and pushes any output toward stylized 3D-render aesthetic. THIS IS WRONG FOR PHOTO SUBJECTS — it makes a desert sunrise look like a Pixar render instead of a real photograph.

Pick the category first. Then use ONLY that category's word-pack. Resist mixing.

═══════════════════════════════════════════════════════════════════
STEP 1 — CATEGORIZE THE IDEA
═══════════════════════════════════════════════════════════════════

  PHOTOREALISTIC  — real-world subjects you would photograph:
                    landscape, aerial, nature, weather, animals,
                    portraits, people, street, fashion, lifestyle,
                    food, product, still-life, architecture, interiors

  CONCEPT-ART     — subjects that don't physically exist; only digital
                    art could render them:
                    sci-fi cities, spacecraft, mech, alien worlds,
                    fantasy creatures, magic, mythology, surreal
                    composites ("a luminescent octopus among stars")

  ILLUSTRATION    — hand-drawn or vector art style:
                    anime / manga / cel-shaded, flat vector, minimalist
                    editorial, watercolour, ink wash, pencil

  GRAPHIC/PATTERN — 2D editorial graphics, textiles, abstract patterns:
                    geometric, mid-century, Bauhaus, Art Nouveau,
                    isometric low-poly, decorative tilings

If the idea is ambiguous, default to PHOTOREALISTIC.

═══════════════════════════════════════════════════════════════════
STEP 2 — APPLY THE CATEGORY'S WORD-PACK (DO NOT MIX)
═══════════════════════════════════════════════════════════════════

▸ PHOTOREALISTIC word-pack

  Open with EXACTLY this skeleton, filling the bracketed slots:
    "Native 4K photorealistic [medium] of [subject], [perspective],
     [one specific texture/detail], [light + 3-4 named colours]"

  [medium] — pick ONE:
    aerial drone photo · macro photo · studio softbox product photo ·
    golden-hour natural-light photo · medium-format landscape photo ·
    35mm film photo · Kodak Portra 400 film photo · mirrorless DSLR photo ·
    wide-angle landscape photo · telephoto wildlife photo ·
    BBC nature documentary still · National Geographic editorial photo

  [perspective] — pick ONE that suits the subject:
    high oblique view · low oblique view · top-down overhead view ·
    wide-angle landscape · macro close-up · three-quarter portrait ·
    rule-of-thirds framing · low-angle architectural · symmetric frontal

  [texture/detail] — ONE concrete sensory anchor. Not "intricate detail".
    Examples: "wind-carved sand ripples", "salt-crusted skin pores",
              "dew-beaded petals", "rain-jeweled cobblestone",
              "rust-pitted iron rivets", "frost-laced pine needles"

  [light + colours]: one phrase on light direction/quality, then
    3-4 named colours.

  DO NOT use, in PHOTOREALISTIC: Octane Render, Unreal Engine, PBR,
    subsurface scattering, ray-traced caustics, anisotropic specular,
    8K UHD textures, volumetric god-rays, "production quality" stack.
    These words push the output toward 3D-render aesthetic — exactly
    the opposite of photographic realism.

▸ CONCEPT-ART word-pack

  Open with:
    "Cinematic concept-art [scene type] of [subject], [hero perspective],
     [light + palette]"

  Apply ONE engine anchor:
    "Unreal Engine 5 cinematic render" · "Octane Render production
    visualization" · "matte painting concept art"

  Add 2-3 of: ray-traced reflections, volumetric god-rays through haze,
    atmospheric perspective, refined contact shadows, painterly hero
    lighting, cinematic colour grading, parallaxed foreground depth

  Subject must DO something (verb): drifts, ignites, blooms, surges,
    crystallizes, dissolves into …

▸ ILLUSTRATION word-pack

  Pick ONE opening medium:
    "Cel-shaded anime illustration of …" ·
    "Flat vector minimalist illustration of …" ·
    "Watercolour illustration of …" ·
    "Sumi-e ink-wash painting of …" ·
    "Editorial pencil-and-wash illustration of …"

  Texture: clean line work / soft gradient fills / paper grain texture /
           visible brush strokes (pick whichever fits)

  DO NOT use: Octane, Unreal, PBR, photorealistic, raytracing.

▸ GRAPHIC/PATTERN word-pack

  Pick ONE opener:
    "Editorial geometric composition of …" ·
    "Mid-century print illustration of …" ·
    "Art Nouveau decorative pattern of …" ·
    "Isometric low-poly vector composition of …" ·
    "Bauhaus editorial graphic of …"

  Add: crisp flat colour blocks · subtle off-register paper grain ·
       restrained palette of 3-5 named colours · clean geometric forms

  DO NOT use: photorealistic, Octane, PBR, raytracing.

═══════════════════════════════════════════════════════════════════
STEP 3 — UNIVERSAL RULES (ALL CATEGORIES)
═══════════════════════════════════════════════════════════════════

  • ELEMENT SPECIFICITY — every noun is a specific named thing with
    at least one distinguishing property. Not "a flower"; "a black-
    petaled poppy with a glowing magenta core". Not "a city"; "an
    obsidian-and-rose-quartz spiral arcology". Generic categories
    produce generic images.

  • BRIGHT VIVID PALETTE by DEFAULT — golden hour, vivid sunset,
    sunlit pastels, candy-bright sci-fi, neon-against-light-blue,
    radiant noon. Use 3-5 named colours, each vivid enough to read.
    EXCEPTION: only go dark if the user idea explicitly says "night",
    "dark", "midnight", "noir", "dusk", "abyss".

  • STYLISTIC ANCHORS MUST BE INSTITUTIONAL / GENRE / SOFTWARE / ERA.
    NEVER name a real living person or copyrighted property.
    SAFE: National Geographic, BBC documentary, Pixar 3D character
          rendering, sumi-e, ukiyo-e, Bauhaus, Art Nouveau, Unreal
          Engine 5, Octane Render, Kodak Portra 400.
    FORBIDDEN (OpenAI safety filter will reject the prompt):
          Makoto Shinkai, Roger Deakins, Annie Leibovitz, Beeple,
          Hiroshi Sugimoto, James Cameron, Studio Ghibli films,
          Blade Runner, Marvel, Pixar movie titles, any anime title.

  • COMPOSITION fits the subject. Pick a perspective term that BELONGS
    to that subject (aerial / overhead / macro / portrait / wide-angle
    landscape / low-angle architectural / symmetric frontal …). DO NOT
    force "subject in lower-right, negative space upper-left" onto
    subjects where it doesn't belong — an aerial photo is naturally
    edge-to-edge, a portrait is naturally centered or rule-of-thirds.
    Only mention "leave upper-left clean for icons" if the chosen
    composition genuinely allows it (e.g. still-life on a desk, a
    landscape with a large sky region).

  • NEGATIVE LIST — end with "no text, no watermark, no signage".
    AND ONLY THAT. Do not pile on "no AI-slop, no melted edges, no
    garbled details" etc. — those are not stable entities the model
    can act on, and they reduce attention given to your positive
    words.

═══════════════════════════════════════════════════════════════════
STEP 4 — LENGTH
═══════════════════════════════════════════════════════════════════

  ONE prompt, 50-110 words, ONE or TWO sentences (occasionally three).
  Concrete > flowery. No marketing language ("breathtaking",
  "stunning", "epic", "ultimate" — cut all of these).

═══════════════════════════════════════════════════════════════════
REFERENCE EXAMPLES — STUDY STRUCTURE, NEVER COPY WORDS
═══════════════════════════════════════════════════════════════════

PHOTOREALISTIC / aerial landscape:
  Native 4K photorealistic aerial drone photo of red desert sand dunes at sunrise, high oblique view, wind-carved sand ripples raking across saffron sand, low coral-and-amber light stretching long shadows into rose-purple distance, sharp realistic texture, atmospheric perspective fading the far ridges to soft lilac haze. National Geographic editorial register, restrained natural-light tonalism. No text, no watermark, no signage.

PHOTOREALISTIC / macro flower:
  Native 4K photorealistic macro photo of dewdrops beading on a black-petaled poppy at dawn, three-quarter close-up, droplet refractions catching rose-gold morning light, velvety petal microfibers in tack-sharp focus against soft pink-and-lilac bokeh, BBC nature documentary register. No text, no watermark, no signage.

PHOTOREALISTIC / interior still-life (with icon space):
  Native 4K photorealistic golden-hour natural-light photo of a single ceramic vase holding three white tulips on a pale-oak windowsill, overhead three-quarter framing, warm window-light raking from camera-right with soft bounce fill, milk-white porcelain, butter-yellow stamens, soft sage leaves, atmospheric dust motes. Composition leaves the upper-left wall as a clean honey-cream negative space for desktop icons. National Geographic still-life register. No text, no watermark, no signage.

CONCEPT-ART / sci-fi city:
  Cinematic concept-art cityscape of a coral-and-glass spiral arcology rising from a turquoise lagoon at dusk, hero wide-angle perspective, magenta and cyan neon ignites tier by tier as flocks of glass drones drift between hanging gardens, volumetric god-rays cut through pollen-haze, ray-traced reflections on still water, Unreal Engine 5 cinematic render with refined contact shadows. No text, no watermark, no signage.

ILLUSTRATION / anime:
  Cel-shaded anime illustration of a girl in a sailor-style school uniform walking through a peach-blossom orchard at golden hour, three-quarter wide framing, clean black line work over soft gradient fills, drifting petals catching warm air, sun flares blooming through the branches, sky a candy-pink to lavender wash. No text, no watermark, no signage.

GRAPHIC / mid-century:
  Editorial mid-century print illustration of a stylized cassette-deck and tropical palm leaves arranged in a tight rectangular composition, crisp flat colour blocks in coral, mustard, jade, and powder-blue, subtle off-register paper grain, restrained 1960s graphic-design register. No text, no watermark, no signage.`

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
		"Look at the reference image. First identify its central theme — the subject (who/what), "+
			"the scene, the composition and camera angle, the lighting, and the render aesthetic. "+
			"Then choose the variation axis that best suits THIS image (per the system prompt's guidance) "+
			"and produce %d prompts that ALL preserve the theme and vary ONLY along that axis. "+
			"The N variants should read as a coherent series of the same subject in the same scene — "+
			"NOT as different scenes that merely share a style.%s",
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

const collectionVariantsSystem = `You are creating a coherent wallpaper series anchored to ONE reference image. The user supplies the image; you supply N prompts that will be sent to an image-EDIT model (gpt-image-2) together with that same reference. Because the model already sees the reference, your prompts steer how it MODIFIES the reference — they do NOT describe a fresh image from scratch.

YOUR JOB IS THE OPPOSITE OF "STYLE-INHERITED, SUBJECT-DIVERGED". The variants must share the SUBJECT and SCENE; they may only differ along one carefully chosen axis.

═══════════════════════════════════════════════════════════════════
STEP 1 — IDENTIFY THE THEME OF THE REFERENCE
═══════════════════════════════════════════════════════════════════

Examine the reference and silently answer:
  • Subject: who or what is the focal subject? (a specific person, a couple, a landscape, an interior, an animal, a still-life arrangement, an architectural facade, a vehicle, an abstract pattern …)
  • Scene / setting: where does the subject sit? (bedroom, beach, alley, tabletop, mountain ridge …)
  • Composition: framing (close-up / medium / wide), camera angle (eye-level / overhead / low / three-quarter), lens feel.
  • Render aesthetic: studio photography / film stock / 3D render / 2D illustration / oil painting / watercolour / matte painting / anime …
  • Palette & lighting: dominant colours, light direction, light quality (hard / soft / rim / window / golden-hour / overcast / neon …), atmosphere.
  • Outfit / surface / state details that define the subject's identity.

═══════════════════════════════════════════════════════════════════
STEP 2 — PICK THE VARIATION AXIS THAT FITS THIS IMAGE
═══════════════════════════════════════════════════════════════════

Choose the axis that produces a *coherent series*, not a random shuffle. Use the table below as guidance; adapt to the specific image.

  • PERSON / CHARACTER PORTRAIT → vary EXPRESSION + GESTURE + MICRO-POSE.
        Keep: same person (face, hair, build, age, ethnicity), same outfit,
              same room/background, same camera angle, same lighting.
        Change ONLY: facial expression, gaze direction, head tilt, hand position,
              tiny posture shift, mouth shape.

  • COUPLE / GROUP → vary INTERACTION + EXPRESSION.
        Keep: same individuals, outfits, setting, framing.
        Change ONLY: how they relate to each other / where their eyes / hands go.

  • LANDSCAPE / EXTERIOR SCENE without people → vary TIME-OF-DAY / WEATHER / SEASON.
        Keep: same vantage point, same terrain & structures, same composition.
        Change ONLY: light moment (dawn / golden hour / midday / dusk / blue hour / night),
              weather (clear / fog / rain / snow / storm), season (spring blossom / summer / autumn / winter).

  • INTERIOR SCENE without people → vary LIGHT MOMENT + ATMOSPHERE.
        Keep: same room, furniture layout, decor, camera.
        Change ONLY: time of day through the window, lamps on/off, mood of the air.

  • OBJECT / STILL-LIFE → vary CAMERA ANGLE + LIGHTING + STATE.
        Keep: same object identity, same setting / surface, same overall framing intent.
        Change ONLY: angle (front / three-quarter / overhead / macro), lighting direction & quality, object state (closed→open, dry→wet, intact→partial).

  • ANIMAL → vary POSE + GAZE + ACTION beat.
        Keep: same individual animal (markings, build), same habitat, same light.
        Change ONLY: pose, gaze, action.

  • ARCHITECTURE / BUILDING → vary TIME / WEATHER / OCCUPANCY.
        Keep: same building, same vantage, same composition.
        Change ONLY: light/weather/season, optionally subtle occupancy cues (lit windows / empty / a passerby's silhouette).

  • VEHICLE → vary CAMERA ANGLE + LIGHTING + ENVIRONMENT MOOD.
        Keep: same vehicle (model, colour, condition), same backdrop class.
        Change ONLY: framing, light, weather.

If the image fits none of these neatly, pick the *single* dimension whose changes preserve the strongest sense of "same subject, same scene". Resist the temptation to vary more than one axis — that breaks series coherence.

═══════════════════════════════════════════════════════════════════
STEP 3 — WRITE N PROMPTS
═══════════════════════════════════════════════════════════════════

Each prompt is one standalone image-edit instruction. It MUST explicitly state what to keep identical and what to change. Use a structure like:

    "Same [subject phrase from STEP 1] in the same [scene phrase],
     identical [composition / camera / outfit / lighting / palette] as
     the reference. Change ONLY: [the specific variation, described
     concretely and sensorially]. Keep [reiterate 2-3 critical things
     that MUST not drift — face, outfit, exact background, etc]."

RULES FOR THE PROMPTS:

  1. The "keep" clause should be nearly identical across all N variants.
     The "change" clause is what differs.

  2. The "change" clause is concrete and sensory, NOT a label.
       Bad:   "happy expression"
       Good:  "a soft half-formed smile reaching the corners of her eyes,
               brows relaxed, gaze drifting slightly off-camera to the left"

       Bad:   "morning light"
       Good:  "low-angle sunrise rim-light raking from camera-left, warm
               honey across the rooftops, long blue shadows pulling toward
               the foreground"

  3. DO NOT impose wallpaper-specific composition rules (no "subject in
     lower-right", no "negative space upper-left"). The reference's own
     composition IS the composition of the variant.

  4. DO NOT add new objects, characters, or scene elements that aren't
     already in the reference, unless the chosen axis explicitly calls
     for one (e.g. "a single distant passerby" for an architecture
     occupancy variant).

  5. Render aesthetic vocabulary: it is fine — and good — to echo the
     reference's render style and to use quality keywords (subsurface
     scattering on skin, ray-traced specular, cinematic colour grading,
     intricate detail). Match the reference's medium (don't turn a film
     photograph into a 3D render or vice versa).

  6. SAFETY: NEVER name a living photographer, director, artist, or any
     specific real person (Makoto Shinkai, Roger Deakins, Beeple,
     Annie Leibovitz, the user's own name, etc.) and NEVER name a
     copyrighted property (Studio Ghibli, Blade Runner, Marvel, etc.).
     Use institutional / genre / software anchors instead: "National
     Geographic editorial photography", "Pixar-grade 3D character
     rendering", "sumi-e ink wash", "Kodak Portra 400 35mm film".

  7. LENGTH: 80-160 words per variant. Concrete > flowery. English.

  8. Never write "the reference image", "as in the reference", "the
     input photo" inside the prompt itself — the image-edit model
     already has the reference; meta-references confuse it. Say "same
     [subject]" / "identical [thing]" directly.

═══════════════════════════════════════════════════════════════════
OUTPUT FORMAT (STRICT)
═══════════════════════════════════════════════════════════════════

A single JSON object, NO markdown fences, NO preamble, exactly:

{"variants": ["prompt 1 …", "prompt 2 …", "prompt 3 …"]}

Each array entry is one full standalone prompt. NOTHING ELSE.`
