package handler

import (
	_ "embed"
	"encoding/json"
	"net/http"

	"github.com/wallpaper/backend/internal/pkg/response"
)

// Embedded at build time. The macOS client and the /download/mac page both
// read this manifest — the canonical human-readable mirror lives in
// macos/CHANGELOG.md (keep the two in sync when you ship a release).
//
//go:embed mac_release.json
var macReleaseJSON []byte

type ReleaseHandler struct{}

func NewReleaseHandler() *ReleaseHandler {
	return &ReleaseHandler{}
}

// GetMacRelease returns the macOS client release manifest wrapped in the
// standard {code, message, data} envelope. The data field is the embedded
// JSON verbatim via json.RawMessage so we don't pay an unmarshal/remarshal
// round-trip on every request.
func (h *ReleaseHandler) GetMacRelease(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "public, max-age=300")
	response.OK(w, json.RawMessage(macReleaseJSON))
}
