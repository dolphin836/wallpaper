package model

import (
	"database/sql/driver"
	"encoding/json"
	"fmt"
)

// I18n holds per-language overrides for one user-visible text column,
// stored as a JSONB map keyed by UI language tag ("en", "zh-CN", "zh-TW",
// "ja"). The base column keeps the original text (whatever language the
// author wrote it in); API handlers replace it with the matching override
// before serialization. Translations are written offline by cmd/i18nfill —
// the API and worker never call the LLM, so a missing key simply falls
// back to the original text.
//
// The field is tagged json:"-" everywhere: the public API exposes only the
// already-localized base field, and the Redis caches that store these rows
// are keyed per language for the same reason.
type I18n map[string]string

func (m I18n) Value() (driver.Value, error) {
	if len(m) == 0 {
		return "{}", nil
	}
	b, err := json.Marshal(m)
	return string(b), err
}

func (m *I18n) Scan(v any) error {
	switch src := v.(type) {
	case nil:
		*m = nil
		return nil
	case []byte:
		return json.Unmarshal(src, m)
	case string:
		return json.Unmarshal([]byte(src), m)
	default:
		return fmt.Errorf("i18n: unsupported scan type %T", v)
	}
}

// Pick returns the translation for lang, or fallback (the original text)
// when the map has no non-empty entry for it.
func (m I18n) Pick(lang, fallback string) string {
	if s := m[lang]; s != "" {
		return s
	}
	return fallback
}
