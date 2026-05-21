package llm

// Anthropic Claude pricing as of 2026 (USD per 1M tokens). Pricing for
// extended-cache-write at 1h-TTL is not listed because we don't use it;
// the cache_creation_tokens counter is billed at the 5-minute rate.
//
// Update this table whenever Anthropic publishes new pricing — there is
// no live "get pricing" API endpoint, so it's hand-maintained.
type price struct {
	Input         float64 // per 1M
	Output        float64 // per 1M
	CacheRead     float64 // per 1M (typically 10% of Input)
	CacheCreation float64 // per 1M, 5-minute TTL (1.25x Input)
}

var modelPricing = map[string]price{
	// Anthropic Claude.
	"claude-opus-4-7":   {Input: 5.00, Output: 25.00, CacheRead: 0.50, CacheCreation: 6.25},
	"claude-opus-4-6":   {Input: 5.00, Output: 25.00, CacheRead: 0.50, CacheCreation: 6.25},
	"claude-opus-4-5":   {Input: 5.00, Output: 25.00, CacheRead: 0.50, CacheCreation: 6.25},
	"claude-sonnet-4-6": {Input: 3.00, Output: 15.00, CacheRead: 0.30, CacheCreation: 3.75},
	"claude-sonnet-4-5": {Input: 3.00, Output: 15.00, CacheRead: 0.30, CacheCreation: 3.75},
	"claude-haiku-4-5":  {Input: 1.00, Output: 5.00, CacheRead: 0.10, CacheCreation: 1.25},

	// OpenAI image generation. Per-token billing — output tokens include
	// the generated pixels, so cost scales with image resolution. 4K
	// (3840×2160) high-quality renders ~$0.15–0.20.
	"gpt-image-2":      {Input: 8.00, Output: 30.00, CacheRead: 0, CacheCreation: 0},
	"gpt-image-1.5":    {Input: 8.00, Output: 32.00, CacheRead: 0, CacheCreation: 0},
	"gpt-image-1":      {Input: 8.00, Output: 30.00, CacheRead: 0, CacheCreation: 0},
	"gpt-image-1-mini": {Input: 2.50, Output: 8.00, CacheRead: 0, CacheCreation: 0},
}

// CostUSD computes the dollar cost of a single Claude call given token
// counts. Returns 0 for an unknown model so a typo doesn't blow up
// accounting — the row still gets inserted, just with $0 attribution.
func CostUSD(model string, inputTokens, outputTokens, cacheReadTokens, cacheCreationTokens int) float64 {
	p, ok := modelPricing[model]
	if !ok {
		return 0
	}
	return (float64(inputTokens)*p.Input +
		float64(outputTokens)*p.Output +
		float64(cacheReadTokens)*p.CacheRead +
		float64(cacheCreationTokens)*p.CacheCreation) / 1_000_000.0
}

// Recorder is the small contract pkg/llm needs to log a call's token
// usage. Implementing it from a different package (e.g. repo) keeps
// pkg/llm a dependency-free leaf — only the API server and CLI tools
// have to know about persistence.
type Recorder interface {
	Record(purpose, model string, inputTokens, outputTokens, cacheReadTokens, cacheCreationTokens int) error
}

// noopRecorder is the zero-value Recorder — used when callers don't
// pass one (e.g. local dev without a DB connection).
type noopRecorder struct{}

func (noopRecorder) Record(string, string, int, int, int, int) error { return nil }
