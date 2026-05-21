// aigen calls OpenAI's gpt-image-2 to produce a wallpaper-sized PNG.
// Optionally uploads the result to wallpaperexchange via the regular
// /wallpapers endpoint so the existing worker pipeline (thumb / preview
// / variants / Claude autotag) runs on it just like a user upload.
//
// China outbound to api.openai.com is blocked from the prod Aliyun box,
// so this CLI is designed to run from a developer Mac — set DB_HOST /
// DB_PORT to point at a local SSH tunnel into prod Postgres for the
// llm_usage ledger entry, or omit the DB envs to skip cost logging.
//
// Usage:
//
//	# generate a 4K landscape image, just save to /tmp
//	./aigen --prompt "minimal teal gradient with subtle film grain"
//
//	# generate + upload (you'll need a valid admin JWT)
//	./aigen --prompt "..." --upload --token "$WPE_ADMIN_TOKEN"
//
//	# explore prompts cheaply with gpt-image-1-mini at 1024² ($0.02)
//	./aigen --prompt "..." --model gpt-image-1-mini --size 1024x1024
package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"mime/multipart"
	"net/http"
	"os"
	"strings"
	"time"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/config"
	"github.com/wallpaper/backend/internal/pkg/llm"
	"github.com/wallpaper/backend/internal/repo"
)

const openaiImagesURL = "https://api.openai.com/v1/images/generations"

func main() {
	var (
		prompt     string
		size       string
		model      string
		count      int
		outPrefix  string
		upload     bool
		apiBaseURL string
		token      string
		categoryID int64
		title      string
		timeout    time.Duration
	)
	flag.StringVar(&prompt, "prompt", "", "image prompt (required)")
	flag.StringVar(&size, "size", "3840x2160", "output WxH — multiples of 16, max edge 3840, total pixels ≤ 8.3MP")
	flag.StringVar(&model, "model", "gpt-image-2", "OpenAI model: gpt-image-2 | gpt-image-1.5 | gpt-image-1-mini")
	flag.IntVar(&count, "count", 1, "how many images to generate (sequential, not parallel — easy on rate limits)")
	flag.StringVar(&outPrefix, "out", "", "local PNG output path prefix (default: /tmp/wxch-aigen-<ts>)")
	flag.BoolVar(&upload, "upload", false, "upload to wallpaperexchange after generation")
	flag.StringVar(&apiBaseURL, "api", "https://api.wallpaperexchange.com/api/v1", "wallpaper API base URL for --upload")
	flag.StringVar(&token, "token", os.Getenv("WPE_ADMIN_TOKEN"), "admin JWT for upload (or env WPE_ADMIN_TOKEN)")
	flag.Int64Var(&categoryID, "category", 0, "optional category_id to attach on upload (0 = let autotag pick)")
	flag.StringVar(&title, "title", "", "optional title on upload (empty = let autotag pick)")
	flag.DurationVar(&timeout, "timeout", 5*time.Minute, "HTTP timeout per image (4K can run 60-120s)")
	flag.Parse()

	if strings.TrimSpace(prompt) == "" {
		log.Fatal("--prompt is required")
	}
	apiKey := os.Getenv("OPENAI_API_KEY")
	if apiKey == "" {
		log.Fatal("OPENAI_API_KEY env not set")
	}
	if upload && token == "" {
		log.Fatal("--upload requires --token <admin JWT> or env WPE_ADMIN_TOKEN")
	}

	// DB is optional — we use it only to record llm_usage so the admin
	// dashboard can show AI spend. If the SSH tunnel isn't running
	// we still want generation to work.
	var usageRepo *repo.LLMUsageRepo
	if cfg, err := config.Load(); err == nil {
		if db, err := gorm.Open(postgres.Open(cfg.DB.DSN()), &gorm.Config{}); err == nil {
			usageRepo = repo.NewLLMUsageRepo(db)
		} else {
			fmt.Printf("(warn) DB unreachable, skipping llm_usage ledger: %v\n", err)
		}
	}

	if outPrefix == "" {
		outPrefix = fmt.Sprintf("/tmp/wxch-aigen-%d", time.Now().Unix())
	}

	ctx := context.Background()
	client := &http.Client{Timeout: timeout}

	for i := 0; i < count; i++ {
		fmt.Printf("\n==> [%d/%d] %s @ %s\n", i+1, count, model, size)
		t0 := time.Now()

		data, usage, err := generate(ctx, client, apiKey, model, prompt, size)
		if err != nil {
			fmt.Printf("    FAILED: %v\n", err)
			continue
		}

		path := fmt.Sprintf("%s-%d.png", outPrefix, i+1)
		if err := os.WriteFile(path, data, 0644); err != nil {
			fmt.Printf("    write failed: %v\n", err)
			continue
		}
		fmt.Printf("    saved → %s  (%.1f MB, %.1fs)\n",
			path, float64(len(data))/1024/1024, time.Since(t0).Seconds())

		costUSD := llm.CostUSD(model, usage.InputTokens, usage.OutputTokens, 0, 0)
		fmt.Printf("    tokens: in=%d out=%d  cost ≈ $%.4f\n",
			usage.InputTokens, usage.OutputTokens, costUSD)

		if usageRepo != nil {
			if err := usageRepo.Record("aigen", model, usage.InputTokens, usage.OutputTokens, 0, 0); err != nil {
				fmt.Printf("    (warn) llm_usage record failed: %v\n", err)
			}
		}

		if upload {
			if err := uploadFile(ctx, client, apiBaseURL, token, path, title, prompt, categoryID); err != nil {
				fmt.Printf("    upload failed: %v\n", err)
				continue
			}
			fmt.Printf("    uploaded ✓\n")
		}
	}
}

type usageReport struct {
	InputTokens  int
	OutputTokens int
}

// generate calls the OpenAI Images API and returns the decoded PNG bytes
// plus token usage. The gpt-image-* family already returns b64_json by
// default, and the legacy `response_format` parameter is now rejected
// (400 unknown_parameter), so we don't send it.
func generate(ctx context.Context, client *http.Client, apiKey, model, prompt, size string) ([]byte, usageReport, error) {
	payload, _ := json.Marshal(map[string]any{
		"model":  model,
		"prompt": prompt,
		"size":   size,
		"n":      1,
	})

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, openaiImagesURL, bytes.NewReader(payload))
	if err != nil {
		return nil, usageReport{}, err
	}
	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return nil, usageReport{}, fmt.Errorf("http: %w", err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return nil, usageReport{}, fmt.Errorf("openai %d: %s", resp.StatusCode, snippet(raw, 400))
	}

	// gpt-image-2 returns: { data: [{b64_json, ...}], usage: {input_tokens, output_tokens, ...} }
	// gpt-image-1 returns the same shape — usage may be absent on older
	// models but the JSON decoder just leaves zeros, which is fine.
	var out struct {
		Data []struct {
			B64JSON string `json:"b64_json"`
			URL     string `json:"url"`
		} `json:"data"`
		Usage struct {
			InputTokens  int `json:"input_tokens"`
			OutputTokens int `json:"output_tokens"`
		} `json:"usage"`
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil, usageReport{}, fmt.Errorf("decode: %w (body %s)", err, snippet(raw, 200))
	}
	if len(out.Data) == 0 || out.Data[0].B64JSON == "" {
		return nil, usageReport{}, fmt.Errorf("no b64_json in response (got: %s)", snippet(raw, 200))
	}
	img, err := base64.StdEncoding.DecodeString(out.Data[0].B64JSON)
	if err != nil {
		return nil, usageReport{}, fmt.Errorf("b64 decode: %w", err)
	}
	return img, usageReport{InputTokens: out.Usage.InputTokens, OutputTokens: out.Usage.OutputTokens}, nil
}

// uploadFile POSTs the generated PNG to /wallpapers as a regular upload.
// Server-side this fires the wallpaper.uploaded Kafka event so the
// existing worker pipeline (thumb/preview/variants/autotag) takes over
// — no special-casing for AI-generated rows.
func uploadFile(ctx context.Context, client *http.Client, apiBase, token, path, title, prompt string, categoryID int64) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()

	var body bytes.Buffer
	w := multipart.NewWriter(&body)

	part, err := w.CreateFormFile("file", "ai-generated.png")
	if err != nil {
		return err
	}
	if _, err := io.Copy(part, f); err != nil {
		return err
	}

	// title: caller's --title wins; otherwise blank so the worker's
	// autotag step assigns one (cleaner than dumping the prompt verbatim
	// as a title, which is usually too long and chatty).
	if title != "" {
		_ = w.WriteField("title", truncate(title, 200))
	}
	// description: stuff the prompt in here for traceability — useful
	// later when the admin wonders "what did I ask for?".
	_ = w.WriteField("description", "AI generated. Prompt: "+truncate(prompt, 1000))
	if categoryID > 0 {
		_ = w.WriteField("category_id", fmt.Sprintf("%d", categoryID))
	}
	if err := w.Close(); err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, apiBase+"/wallpapers", &body)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", w.FormDataContentType())

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return fmt.Errorf("upload %d: %s", resp.StatusCode, snippet(raw, 400))
	}
	return nil
}

func truncate(s string, n int) string {
	if len(s) > n {
		return s[:n]
	}
	return s
}

func snippet(b []byte, n int) string {
	if len(b) > n {
		return string(b[:n]) + "…"
	}
	return string(b)
}
