// aigen is the local-Mac AI wallpaper pipeline.
//
// Subcommands:
//
//	aigen preview "<idea>"      Expand the idea with Claude + render a
//	                            cheap 1024² preview with gpt-image-1-mini.
//	                            Result lands in ai-wallpapers/pending/<id>/.
//
//	aigen finalize <id>         Take an approved pending preview and
//	                            render the matching 4K (3840×2160) frame
//	                            with gpt-image-2. Moves dir to approved/.
//
//	aigen reject <id>           Discard a pending preview (deletes dir).
//
//	aigen list [pending|        Print one-line summaries of the named
//	            approved|       state buckets (default: all).
//	            uploaded]
//
//	aigen publish [<id>]        Upload approved wallpapers to the site via
//	    [--all]                 the admin /wallpapers/ai-upload endpoint.
//	                            Without args runs interactive picker on
//	                            the only approved item, or prompts if many.
//	                            --all uploads every approved row.
//
// Hard-coded composition + safety constraints live in the constants
// near the top of this file. They're appended to whatever Claude returns
// so we don't trust the LLM to enforce them.
//
// Environment:
//   OPENAI_API_KEY      required for preview / finalize
//   ANTHROPIC_API_KEY   required for preview (prompt expansion)
//   WPE_ADMIN_TOKEN     required for publish (admin JWT)
//   DB_HOST / DB_PORT / ...  optional — when reachable, llm_usage rows
//                            are written for every Claude + OpenAI call
//                            so the admin dashboard sees the spend.
package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"time"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	gormlogger "gorm.io/gorm/logger"

	"github.com/wallpaper/backend/internal/config"
	"github.com/wallpaper/backend/internal/pkg/llm"
	"github.com/wallpaper/backend/internal/repo"
)

// Hard-coded constraints, appended to every refined prompt before it
// gets sent to OpenAI. Edit here when our composition guidelines change;
// no need to touch Claude's system prompt.
const (
	finalSize   = "3840x2160" // 16:9 desktop 4K
	previewSize = "1024x1024" // square — cheapest size for a vibe check
	finalModel  = "gpt-image-2"
	miniModel   = "gpt-image-1-mini"

	compositionAndSafety = ". The main subject is centered in the frame with " +
		"at least 25% margin from every edge so the image can be cropped to " +
		"phone (9:19.5) and tablet (3:4) aspect ratios without losing key " +
		"content. No people, no faces, no text, no logos, no brand marks, no " +
		"watermarks. Cinematic light, rich tonal depth, contemplative mood — " +
		"suitable as a long-stare desktop wallpaper."

	openaiImagesURL = "https://api.openai.com/v1/images/generations"

	storeRoot = "ai-wallpapers"
)

type meta struct {
	ID             string    `json:"id"`
	Idea           string    `json:"idea"`
	RefinedPrompt  string    `json:"refined_prompt"`  // Claude output (no constraints yet)
	FullPrompt     string    `json:"full_prompt"`     // refined + appended constraints
	Status         string    `json:"status"`          // pending | approved | uploaded
	PreviewModel   string    `json:"preview_model"`
	PreviewSize    string    `json:"preview_size"`
	PreviewCostUSD float64   `json:"preview_cost_usd"`
	FinalModel     string    `json:"final_model,omitempty"`
	FinalSize      string    `json:"final_size,omitempty"`
	FinalCostUSD   float64   `json:"final_cost_usd,omitempty"`
	ExpandCostUSD  float64   `json:"expand_cost_usd"`
	CreatedAt      time.Time `json:"created_at"`
	FinalizedAt    *time.Time `json:"finalized_at,omitempty"`
	UploadedAt     *time.Time `json:"uploaded_at,omitempty"`
	RemoteID       int64     `json:"remote_id,omitempty"`
	RemoteSlug     string    `json:"remote_slug,omitempty"`
}

func main() {
	flag.Usage = printUsage
	flag.Parse()
	args := flag.Args()

	if len(args) == 0 {
		printUsage()
		os.Exit(1)
	}
	cmd, rest := args[0], args[1:]

	switch cmd {
	case "preview":
		if len(rest) == 0 {
			fail("aigen preview requires an idea string\n  e.g. aigen preview \"雾气山脉日出\"")
		}
		runPreview(strings.Join(rest, " "))
	case "finalize":
		if len(rest) == 0 {
			fail("aigen finalize requires an id\n  e.g. aigen finalize 2026-05-21-184530-a7f3")
		}
		runFinalize(rest[0])
	case "reject":
		if len(rest) == 0 {
			fail("aigen reject requires an id")
		}
		runReject(rest[0])
	case "list":
		filter := ""
		if len(rest) > 0 {
			filter = rest[0]
		}
		runList(filter)
	case "publish":
		runPublish(rest)
	default:
		fail("unknown subcommand %q\n", cmd)
	}
}

// ─────────── preview ───────────

func runPreview(idea string) {
	openAIKey := mustEnv("OPENAI_API_KEY")
	anthropicKey := mustEnv("ANTHROPIC_API_KEY")

	usageRepo := tryDBConnect()
	llmClient := llm.New(anthropicKey, usageRepo)

	ctx := context.Background()
	fmt.Printf("==> Expanding prompt with Claude…\n")
	t0 := time.Now()
	refined, err := llmClient.ExpandWallpaperPrompt(ctx, idea)
	if err != nil {
		fail("expand prompt failed: %v", err)
	}
	fmt.Printf("    refined: %s\n", refined)
	fmt.Printf("    %.1fs\n", time.Since(t0).Seconds())

	full := refined + compositionAndSafety

	fmt.Printf("==> Generating preview (%s @ %s)…\n", miniModel, previewSize)
	t0 = time.Now()
	pngData, usage, err := openaiGenerate(ctx, openAIKey, miniModel, full, previewSize)
	if err != nil {
		fail("preview generation failed: %v", err)
	}
	cost := llm.CostUSD(miniModel, usage.in, usage.out, 0, 0)
	if usageRepo != nil {
		_ = usageRepo.Record("aigen_preview", miniModel, usage.in, usage.out, 0, 0)
	}
	fmt.Printf("    %.1fs, %d input + %d output tokens, ≈ $%.4f\n",
		time.Since(t0).Seconds(), usage.in, usage.out, cost)

	id := newID()
	dir := filepath.Join(storeRoot, "pending", id)
	if err := os.MkdirAll(dir, 0755); err != nil {
		fail("mkdir: %v", err)
	}
	previewPath := filepath.Join(dir, "mini.png")
	if err := os.WriteFile(previewPath, pngData, 0644); err != nil {
		fail("write preview: %v", err)
	}

	m := &meta{
		ID:             id,
		Idea:           idea,
		RefinedPrompt:  refined,
		FullPrompt:     full,
		Status:         "pending",
		PreviewModel:   miniModel,
		PreviewSize:    previewSize,
		PreviewCostUSD: cost,
		CreatedAt:      time.Now().UTC(),
	}
	if err := writeMeta(dir, m); err != nil {
		fail("write meta: %v", err)
	}

	fmt.Printf("\n    📂 %s\n", previewPath)
	if err := openLocally(previewPath); err != nil {
		// non-fatal — just print the path and continue.
		fmt.Printf("    (couldn't auto-open: %v)\n", err)
	}

	fmt.Printf(`
==> Review the preview. Next step:
    ✓ keep:    ./scripts/wallpaper-gen.sh --finalize %s
    ✗ reject:  ./scripts/wallpaper-gen.sh --reject   %s
`, id, id)
}

// ─────────── finalize ───────────

func runFinalize(id string) {
	openAIKey := mustEnv("OPENAI_API_KEY")
	usageRepo := tryDBConnect()

	pendingDir := filepath.Join(storeRoot, "pending", id)
	m, err := readMeta(pendingDir)
	if err != nil {
		fail("read pending meta: %v", err)
	}
	if m.Status != "pending" {
		fail("expected status=pending, got %q", m.Status)
	}

	ctx := context.Background()
	fmt.Printf("==> Generating 4K (%s @ %s) — this may take 60–120s…\n", finalModel, finalSize)
	t0 := time.Now()
	pngData, usage, err := openaiGenerate(ctx, openAIKey, finalModel, m.FullPrompt, finalSize)
	if err != nil {
		fail("final generation failed: %v", err)
	}
	cost := llm.CostUSD(finalModel, usage.in, usage.out, 0, 0)
	if usageRepo != nil {
		_ = usageRepo.Record("aigen_final", finalModel, usage.in, usage.out, 0, 0)
	}
	fmt.Printf("    %.1fs, %d input + %d output tokens, ≈ $%.4f\n",
		time.Since(t0).Seconds(), usage.in, usage.out, cost)

	// Move pending → approved, then write the new full.png.
	approvedDir := filepath.Join(storeRoot, "approved", id)
	if err := os.MkdirAll(filepath.Dir(approvedDir), 0755); err != nil {
		fail("mkdir approved parent: %v", err)
	}
	if err := os.Rename(pendingDir, approvedDir); err != nil {
		fail("move pending → approved: %v", err)
	}
	fullPath := filepath.Join(approvedDir, "full.png")
	if err := os.WriteFile(fullPath, pngData, 0644); err != nil {
		fail("write full.png: %v", err)
	}

	now := time.Now().UTC()
	m.Status = "approved"
	m.FinalModel = finalModel
	m.FinalSize = finalSize
	m.FinalCostUSD = cost
	m.FinalizedAt = &now
	if err := writeMeta(approvedDir, m); err != nil {
		fail("update meta: %v", err)
	}

	fmt.Printf("\n    📂 %s (%.1f MB)\n", fullPath, float64(len(pngData))/1024/1024)
	_ = openLocally(fullPath)

	fmt.Printf(`
==> Approved. Publish when ready:
    ./scripts/wallpaper-publish.sh %s
`, id)
}

// ─────────── reject ───────────

func runReject(id string) {
	pendingDir := filepath.Join(storeRoot, "pending", id)
	if _, err := os.Stat(pendingDir); err != nil {
		fail("no such pending id: %s", id)
	}
	if err := os.RemoveAll(pendingDir); err != nil {
		fail("delete: %v", err)
	}
	fmt.Printf("Rejected %s.\n", id)
}

// ─────────── list ───────────

func runList(filter string) {
	buckets := []string{"pending", "approved", "uploaded"}
	if filter != "" {
		buckets = []string{filter}
	}
	for _, b := range buckets {
		dir := filepath.Join(storeRoot, b)
		entries, _ := os.ReadDir(dir)
		// Sort newest first by name (IDs start with timestamp).
		sort.Slice(entries, func(i, j int) bool { return entries[i].Name() > entries[j].Name() })

		fmt.Printf("── %s (%d) ──\n", b, len(entries))
		for _, e := range entries {
			m, err := readMeta(filepath.Join(dir, e.Name()))
			if err != nil {
				continue
			}
			idea := m.Idea
			if len(idea) > 50 {
				idea = idea[:50] + "…"
			}
			line := fmt.Sprintf("  %s  %s", m.ID, idea)
			if m.RemoteSlug != "" {
				line += fmt.Sprintf("  →  /wallpaper/%s", m.RemoteSlug)
			}
			fmt.Println(line)
		}
	}
}

// ─────────── publish ───────────

// Publish goes through SSH + `docker exec /bin/wallpaper-import` rather
// than the HTTP API: we already have prod root access for ops, so
// burning an admin JWT into a developer's .env just to publish from
// the same machine is friction we don't need. The CLI inside the api
// container talks straight to MinIO + Postgres + Kafka.
func runPublish(args []string) {
	sshHost := envOrDefault("SSH_HOST", "root@139.224.49.94")
	composeFile := envOrDefault("SSH_DEPLOY_COMPOSE", "/opt/app/wallpaper/docker-compose.yml")
	uploaderUserID := envOrDefault("WPE_AI_UPLOADER_ID", "1")

	approvedDir := filepath.Join(storeRoot, "approved")
	entries, _ := os.ReadDir(approvedDir)
	if len(entries) == 0 {
		fmt.Println("No approved wallpapers to publish.")
		return
	}

	var ids []string
	all := false
	for _, a := range args {
		if a == "--all" {
			all = true
		} else {
			ids = append(ids, a)
		}
	}
	if all || len(ids) == 0 {
		for _, e := range entries {
			ids = append(ids, e.Name())
		}
	}

	for i, id := range ids {
		fmt.Printf("\n[%d/%d] %s\n", i+1, len(ids), id)
		dir := filepath.Join(approvedDir, id)
		m, err := readMeta(dir)
		if err != nil {
			fmt.Printf("    skip: %v\n", err)
			continue
		}
		fullPath := filepath.Join(dir, "full.png")
		if _, err := os.Stat(fullPath); err != nil {
			fmt.Printf("    skip: missing full.png\n")
			continue
		}
		fmt.Printf("    streaming → %s via ssh + docker exec…\n", sshHost)
		remoteID, remoteSlug, err := uploadViaSSH(sshHost, composeFile, uploaderUserID, fullPath, m)
		if err != nil {
			fmt.Printf("    FAILED: %v\n", err)
			continue
		}
		now := time.Now().UTC()
		m.Status = "uploaded"
		m.RemoteID = remoteID
		m.RemoteSlug = remoteSlug
		m.UploadedAt = &now
		if err := writeMeta(dir, m); err != nil {
			fmt.Printf("    (warn) couldn't update meta: %v\n", err)
		}
		dest := filepath.Join(storeRoot, "uploaded", id)
		if err := os.MkdirAll(filepath.Dir(dest), 0755); err != nil {
			fmt.Printf("    (warn) mkdir uploaded: %v\n", err)
		}
		if err := os.Rename(dir, dest); err != nil {
			fmt.Printf("    (warn) move failed: %v\n", err)
		}
		fmt.Printf("    ✓ uploaded id=%d slug=%s\n", remoteID, remoteSlug)
	}

	fmt.Println("\nDone.")
}

// uploadViaSSH pipes the file bytes through `ssh + docker compose exec
// -T api /bin/wallpaper-import`, parses the "OK id=N slug=…" line off
// stdout, and returns the new wallpaper's id + slug.
//
// docker compose exec rather than docker exec keeps the call portable
// across compose v1/v2 container naming.
func uploadViaSSH(sshHost, composeFile, userID, localPath string, m *meta) (int64, string, error) {
	f, err := os.Open(localPath)
	if err != nil {
		return 0, "", fmt.Errorf("open file: %w", err)
	}
	defer f.Close()

	desc := "AI-generated. Prompt: " + truncateRunes(m.Idea, 500)
	if m.RefinedPrompt != "" {
		desc += " // " + truncateRunes(m.RefinedPrompt, 500)
	}

	// -T disables TTY allocation so stdin can stream raw bytes without
	// the terminal doing line-buffering tricks on the PNG payload.
	remoteCmd := fmt.Sprintf(
		"docker compose -f %s exec -T api /bin/wallpaper-import "+
			"--user-id %s --ai "+
			"--filename %q "+
			"--content-type image/png "+
			"--description %q",
		shellQuote(composeFile),
		shellQuote(userID),
		"ai-"+m.ID+".png",
		desc,
	)

	cmd := exec.Command("ssh", sshHost, remoteCmd)
	cmd.Stdin = f
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return 0, "", fmt.Errorf("ssh exec: %w\nstderr: %s", err, stderr.String())
	}

	// Expect a single line like: "OK id=896 slug=foo-bar-1234". Tolerate
	// trailing newlines from ssh.
	line := strings.TrimSpace(stdout.String())
	for _, candidate := range strings.Split(line, "\n") {
		candidate = strings.TrimSpace(candidate)
		if strings.HasPrefix(candidate, "OK id=") {
			var id int64
			var slug string
			if _, err := fmt.Sscanf(candidate, "OK id=%d slug=%s", &id, &slug); err == nil {
				return id, slug, nil
			}
		}
	}
	return 0, "", fmt.Errorf("unexpected output: %s\nstderr: %s", stdout.String(), stderr.String())
}

// shellQuote wraps a string in single quotes for safe inclusion in the
// SSH-remote shell command. ssh runs whatever we pass through /bin/sh,
// so spaces or odd chars in the description would otherwise leak.
func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

// ─────────── OpenAI ───────────

type openaiUsage struct {
	in  int
	out int
}

func openaiGenerate(ctx context.Context, key, model, prompt, size string) ([]byte, openaiUsage, error) {
	payload, _ := json.Marshal(map[string]any{
		"model":  model,
		"prompt": prompt,
		"size":   size,
		"n":      1,
	})
	// 4K renders routinely run 60–120s; allow plenty of headroom.
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, openaiImagesURL, bytes.NewReader(payload))
	if err != nil {
		return nil, openaiUsage{}, err
	}
	req.Header.Set("Authorization", "Bearer "+key)
	req.Header.Set("Content-Type", "application/json")
	client := &http.Client{Timeout: 5 * time.Minute}
	resp, err := client.Do(req)
	if err != nil {
		return nil, openaiUsage{}, fmt.Errorf("http: %w", err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return nil, openaiUsage{}, fmt.Errorf("openai %d: %s", resp.StatusCode, snippet(raw, 400))
	}
	var out struct {
		Data []struct {
			B64JSON string `json:"b64_json"`
		} `json:"data"`
		Usage struct {
			InputTokens  int `json:"input_tokens"`
			OutputTokens int `json:"output_tokens"`
		} `json:"usage"`
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil, openaiUsage{}, fmt.Errorf("decode: %w", err)
	}
	if len(out.Data) == 0 || out.Data[0].B64JSON == "" {
		return nil, openaiUsage{}, fmt.Errorf("no b64_json in response: %s", snippet(raw, 200))
	}
	img, err := base64.StdEncoding.DecodeString(out.Data[0].B64JSON)
	if err != nil {
		return nil, openaiUsage{}, fmt.Errorf("b64 decode: %w", err)
	}
	return img, openaiUsage{in: out.Usage.InputTokens, out: out.Usage.OutputTokens}, nil
}

// ─────────── helpers ───────────

// tryDBConnect returns an LLMUsageRepo bound to a live prod-Postgres
// connection, or nil if anything between config.Load() and a Ping
// fails. Returning a "looks-fine but unreachable" repo would crash later
// inside Record — gorm.Open is lazy, so it doesn't surface a dial
// failure on its own. The Ping closes that gap.
func tryDBConnect() *repo.LLMUsageRepo {
	cfg, err := config.Load()
	if err != nil {
		return nil
	}
	// Silence GORM's default logger so the script's first line isn't a
	// noisy stack trace when the SSH tunnel happens to be down.
	db, err := gorm.Open(postgres.Open(cfg.DB.DSN()), &gorm.Config{
		Logger: gormlogger.Discard,
	})
	if err != nil {
		return nil
	}
	sqlDB, err := db.DB()
	if err != nil {
		return nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := sqlDB.PingContext(ctx); err != nil {
		return nil
	}
	return repo.NewLLMUsageRepo(db)
}

func newID() string {
	b := make([]byte, 2)
	_, _ = rand.Read(b)
	return time.Now().UTC().Format("2006-01-02-150405") + "-" + hex.EncodeToString(b)
}

func writeMeta(dir string, m *meta) error {
	data, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, "meta.json"), data, 0644)
}

func readMeta(dir string) (*meta, error) {
	data, err := os.ReadFile(filepath.Join(dir, "meta.json"))
	if err != nil {
		return nil, err
	}
	var m meta
	if err := json.Unmarshal(data, &m); err != nil {
		return nil, err
	}
	return &m, nil
}

func openLocally(path string) error {
	if runtime.GOOS != "darwin" {
		return fmt.Errorf("auto-open only implemented for macOS")
	}
	return exec.Command("/usr/bin/open", path).Run()
}

func mustEnv(name string) string {
	v := os.Getenv(name)
	if v == "" {
		fail("required env %s is not set", name)
	}
	return v
}

func envOrDefault(name, def string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return def
}

func snippet(b []byte, n int) string {
	if len(b) > n {
		return string(b[:n]) + "…"
	}
	return string(b)
}

// truncateRunes trims a string to N runes (Chinese characters count
// once each — byte truncation would corrupt mid-character).
func truncateRunes(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n])
}

func fail(format string, args ...any) {
	fmt.Fprintln(os.Stderr, fmt.Sprintf(format, args...))
	os.Exit(1)
}

func printUsage() {
	fmt.Fprintln(os.Stderr, strings.TrimSpace(`
aigen — AI wallpaper generation pipeline

USAGE:
  aigen preview "<idea>"        Refine + render mini preview
  aigen finalize <id>           Render 4K final from approved pending
  aigen reject <id>             Discard a pending preview
  aigen list [pending|approved|uploaded]
  aigen publish [<id>] [--all]  Upload approved → remote

Typical flow:
  aigen preview "雾气山脉日出"
  aigen finalize 2026-05-21-184530-a7f3
  aigen publish 2026-05-21-184530-a7f3

ENV:
  OPENAI_API_KEY      preview/finalize
  ANTHROPIC_API_KEY   preview (prompt expansion)
  WPE_ADMIN_TOKEN     publish
`))

	// Add log import if needed.
	_ = log.Default
}
