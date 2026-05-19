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
	"encoding/json"
	"fmt"
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
	client  anthropic.Client
	model   anthropic.Model
	enabled bool
}

// New constructs a Client. Pass an empty apiKey to disable LLM calls — the
// returned client's Classify will always error, which callers (the worker
// hook in particular) interpret as "skip auto-tagging, leave fields blank".
func New(apiKey string) *Client {
	c := anthropic.NewClient(option.WithAPIKey(apiKey))
	return &Client{
		client: c,
		// Opus 4.7 is the latest model. For high-volume classification
		// you may want to switch to claude-sonnet-4-6 (3x cheaper) or
		// claude-haiku-4-5 (5x cheaper) — change this constant.
		model:   anthropic.ModelClaudeOpus4_7,
		enabled: apiKey != "",
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

func contains(list []string, s string) bool {
	for _, v := range list {
		if v == s {
			return true
		}
	}
	return false
}
