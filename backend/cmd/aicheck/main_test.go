package main

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestDownloadPreviewUsesResponseBytesAndContentType(t *testing.T) {
	payload := []byte("RIFF\x00\x00\x00\x00WEBP")
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "image/webp")
		_, _ = w.Write(payload)
	}))
	defer server.Close()

	got, mediaType, err := downloadPreview(context.Background(), server.Client(), server.URL)
	if err != nil {
		t.Fatalf("downloadPreview() error = %v", err)
	}
	if string(got) != string(payload) {
		t.Fatalf("downloadPreview() bytes = %q, want %q", got, payload)
	}
	if mediaType != "image/webp" {
		t.Fatalf("downloadPreview() mediaType = %q, want image/webp", mediaType)
	}
}

func TestDownloadPreviewRejectsOversizedResponse(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "image/webp")
		chunk := make([]byte, 32*1024)
		for written := 0; written <= maxPreviewBytes; written += len(chunk) {
			_, _ = w.Write(chunk)
		}
	}))
	defer server.Close()

	_, _, err := downloadPreview(context.Background(), server.Client(), server.URL)
	if !errors.Is(err, errPreviewTooLarge) {
		t.Fatalf("downloadPreview() error = %v, want errPreviewTooLarge", err)
	}
}
