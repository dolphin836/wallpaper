// [skill: go-team-standards · 错误处理 · 外部IO超时] UGC translation batch call for cmd/i18nfill
package llm

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/anthropics/anthropic-sdk-go"
)

// TranslateItem is one piece of user-generated text handed to
// TranslateBatch. Kind tunes the style rules per text role.
type TranslateItem struct {
	ID   int64  `json:"id"`
	Kind string `json:"kind"` // "tag" | "title" | "description"
	Text string `json:"text"`
}

const translatePrompt = `You are localizing user-generated content for a wallpaper-sharing site whose UI ships in English, Simplified Chinese, Traditional Chinese, and Japanese. Each input item is a tag name, a collection title, or a collection description, written in whatever language its author used.

For every item return all four translations. Rules:
- If the source text is already in one of the four target languages, copy it VERBATIM into that language's field (never rewrite the author's own words).
- "tag" items: keep them short. English tags are lowercase, multi-word joined by hyphens (site convention). No punctuation in CJK tags.
- "title" items: natural, idiomatic phrasing; keep proper nouns, brand names, and emoji as-is.
- "description" items: faithful translation, keep the author's tone and any line breaks.
- zh-TW uses Taiwan terminology (桌布 for wallpaper, 下載, 影片), not mainland terms.
- Japanese: natural app-store style, no excessive keigo.
- Never translate usernames, URLs, or file formats.

Input items (JSON lines):
%s

Return ONLY a JSON object, no markdown fences, in this exact shape:
{"items":[{"id":1,"en":"...","zh_cn":"...","zh_tw":"...","ja":"..."}]}`

// TranslateBatch translates a batch of UGC strings into all four UI
// languages in one call. Returns id → {lang tag → text} using the UI
// language tags ("en", "zh-CN", "zh-TW", "ja") so callers can store the
// map straight into a model.I18n column. Items whose id is missing from
// the response are simply absent from the result — callers retry them on
// the next run rather than failing the whole batch.
func (c *Client) TranslateBatch(ctx context.Context, items []TranslateItem) (map[int64]map[string]string, error) {
	if !c.Enabled() {
		return nil, fmt.Errorf("anthropic api key not configured")
	}
	if len(items) == 0 {
		return map[int64]map[string]string{}, nil
	}

	var b strings.Builder
	for _, it := range items {
		line, err := json.Marshal(it)
		if err != nil {
			return nil, fmt.Errorf("marshal translate item %d: %w", it.ID, err)
		}
		b.Write(line)
		b.WriteByte('\n')
	}

	resp, err := c.client.Messages.New(ctx, anthropic.MessageNewParams{
		Model:     c.model,
		MaxTokens: 16000,
		System: []anthropic.TextBlockParam{
			{Text: fmt.Sprintf(translatePrompt, b.String())},
		},
		Messages: []anthropic.MessageParam{
			anthropic.NewUserMessage(anthropic.NewTextBlock("Output the JSON now.")),
		},
	})
	if err != nil {
		return nil, fmt.Errorf("anthropic api: %w", err)
	}
	c.recordUsage("i18nfill", resp.Usage)

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
		Items []struct {
			ID   int64  `json:"id"`
			EN   string `json:"en"`
			ZhCN string `json:"zh_cn"`
			ZhTW string `json:"zh_tw"`
			JA   string `json:"ja"`
		} `json:"items"`
	}
	if err := json.Unmarshal([]byte(raw), &out); err != nil {
		return nil, fmt.Errorf("parse translations json: %w (first 300 chars: %q)", err, truncateLLM(raw, 300))
	}

	result := make(map[int64]map[string]string, len(out.Items))
	for _, it := range out.Items {
		// All four languages must be present — a partial row would make
		// the UI flip-flop between translated and original text.
		if it.EN == "" || it.ZhCN == "" || it.ZhTW == "" || it.JA == "" {
			continue
		}
		result[it.ID] = map[string]string{
			"en":    it.EN,
			"zh-CN": it.ZhCN,
			"zh-TW": it.ZhTW,
			"ja":    it.JA,
		}
	}
	return result, nil
}
