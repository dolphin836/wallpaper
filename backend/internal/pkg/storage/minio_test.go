package storage

import (
	"encoding/json"
	"fmt"
	"testing"
)

func TestPublicAssetReadPolicyKeepsOriginalsPrivate(t *testing.T) {
	data, err := publicAssetReadPolicy("wallpapers")
	if err != nil {
		t.Fatal(err)
	}
	var policy struct {
		Statement []struct {
			Resource []string `json:"Resource"`
		} `json:"Statement"`
	}
	if err := json.Unmarshal(data, &policy); err != nil {
		t.Fatal(err)
	}
	if len(policy.Statement) != 1 {
		t.Fatalf("got %d statements, want 1", len(policy.Statement))
	}

	resources := make(map[string]bool)
	for _, resource := range policy.Statement[0].Resource {
		resources[resource] = true
	}
	for _, prefix := range []string{"avatars", "frames", "posters", "previews", "thumbs"} {
		want := fmt.Sprintf("arn:aws:s3:::wallpapers/%s/*", prefix)
		if !resources[want] {
			t.Errorf("missing public derived prefix %q", want)
		}
	}
	for _, prefix := range []string{"originals", "videos"} {
		blocked := fmt.Sprintf("arn:aws:s3:::wallpapers/%s/*", prefix)
		if resources[blocked] {
			t.Errorf("protected prefix is public: %q", blocked)
		}
	}
	if resources["arn:aws:s3:::wallpapers/*"] {
		t.Fatal("bucket-wide public read policy returned")
	}
}

func TestObjectKeyFromHistoricalURL(t *testing.T) {
	store := &Storage{
		bucket:    "wallpapers",
		publicURL: "https://wallpaperexchange.com/storage",
	}

	tests := map[string]string{
		"https://wallpaperexchange.com/storage/wallpapers/originals/2026/07/a.jpg": "originals/2026/07/a.jpg",
		"https://old.example/storage/wallpapers/videos/2026/07/a.mp4":              "videos/2026/07/a.mp4",
	}
	for rawURL, want := range tests {
		if got := store.ObjectKeyFromURL(rawURL); got != want {
			t.Errorf("ObjectKeyFromURL(%q) = %q, want %q", rawURL, got, want)
		}
	}
}
