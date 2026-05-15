package middleware

import (
	"net/http"
	"sync"
	"time"

	"github.com/wallpaper/backend/internal/pkg/errcode"
	"github.com/wallpaper/backend/internal/pkg/response"
)

type visitor struct {
	tokens   float64
	lastSeen time.Time
}

// RateLimiter implements a per-IP token bucket rate limiter.
type RateLimiter struct {
	mu       sync.Mutex
	visitors map[string]*visitor
	rate     float64
	burst    float64
}

// NewRateLimiter creates a rate limiter that refills at rate tokens/sec up to burst.
func NewRateLimiter(rate float64, burst float64) *RateLimiter {
	rl := &RateLimiter{
		visitors: make(map[string]*visitor),
		rate:     rate,
		burst:    burst,
	}
	go rl.cleanup()
	return rl
}

func (rl *RateLimiter) cleanup() {
	for {
		time.Sleep(time.Minute)
		rl.mu.Lock()
		for ip, v := range rl.visitors {
			if time.Since(v.lastSeen) > 3*time.Minute {
				delete(rl.visitors, ip)
			}
		}
		rl.mu.Unlock()
	}
}

func (rl *RateLimiter) allow(ip string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	v, exists := rl.visitors[ip]
	if !exists {
		rl.visitors[ip] = &visitor{tokens: rl.burst - 1, lastSeen: time.Now()}
		return true
	}

	elapsed := time.Since(v.lastSeen).Seconds()
	v.lastSeen = time.Now()
	v.tokens += elapsed * rl.rate
	if v.tokens > rl.burst {
		v.tokens = rl.burst
	}

	if v.tokens < 1 {
		return false
	}

	v.tokens--
	return true
}

// Handler returns middleware that rate-limits requests by client IP.
func (rl *RateLimiter) Handler(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !rl.allow(clientIPFor(r)) {
			w.Header().Set("Retry-After", "1")
			response.Error(w, http.StatusTooManyRequests, errcode.ErrRateLimited)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// clientIPFor returns the most trustworthy origin IP available from the
// request. Order matters:
//   1. CF-Connecting-IP — Cloudflare always sets this to the real client
//      IP at its edge, regardless of how many CF hops (Pages → Worker →
//      origin) the request took. This is the only header that's safe even
//      when the request goes Pages → _redirects 200 → api subdomain,
//      because each hop preserves it verbatim.
//   2. X-Real-IP — set by some single-hop proxies (nginx default).
//   3. X-Forwarded-For first entry — the original client when the chain is
//      well-formed. We take the leftmost since the chain is "client, p1, p2".
//   4. r.RemoteAddr — last resort; will be the local proxy address.
func clientIPFor(r *http.Request) string {
	if ip := r.Header.Get("CF-Connecting-IP"); ip != "" {
		return ip
	}
	if ip := r.Header.Get("X-Real-IP"); ip != "" {
		return ip
	}
	if fwd := r.Header.Get("X-Forwarded-For"); fwd != "" {
		if i := indexByte(fwd, ','); i > 0 {
			return trimSpace(fwd[:i])
		}
		return trimSpace(fwd)
	}
	return r.RemoteAddr
}

// Small helpers kept local to avoid importing strings here just for two calls.
func indexByte(s string, c byte) int {
	for i := 0; i < len(s); i++ {
		if s[i] == c {
			return i
		}
	}
	return -1
}
func trimSpace(s string) string {
	a, b := 0, len(s)
	for a < b && (s[a] == ' ' || s[a] == '\t') {
		a++
	}
	for b > a && (s[b-1] == ' ' || s[b-1] == '\t') {
		b--
	}
	return s[a:b]
}
