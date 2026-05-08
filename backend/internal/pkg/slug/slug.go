package slug

import (
	"crypto/rand"
	"encoding/hex"
	"path/filepath"
	"regexp"
	"strings"
	"unicode"

	"golang.org/x/text/unicode/norm"
)

var (
	reNonAlnum  = regexp.MustCompile(`[^a-z0-9]+`)
	reTrimDash  = regexp.MustCompile(`^-+|-+$`)
)

// Generate creates a URL-safe slug from text with a short random suffix.
func Generate(text string) string {
	base := Slugify(text)
	if base == "" {
		base = "item"
	}
	if len(base) > 120 {
		base = base[:120]
	}
	return base + "-" + shortID()
}

// FromFileName creates a slug from a filename (strips extension).
func FromFileName(name string) string {
	name = strings.TrimSuffix(name, filepath.Ext(name))
	return Generate(name)
}

// Slugify converts text to a clean kebab-case slug without suffix.
func Slugify(text string) string {
	text = norm.NFKD.String(text)
	var b strings.Builder
	for _, r := range text {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			b.WriteRune(unicode.ToLower(r))
		} else {
			b.WriteRune('-')
		}
	}
	s := reNonAlnum.ReplaceAllString(b.String(), "-")
	s = reTrimDash.ReplaceAllString(s, "")
	return s
}

func shortID() string {
	b := make([]byte, 4)
	if _, err := rand.Read(b); err != nil {
		return "0000"
	}
	return hex.EncodeToString(b)
}
