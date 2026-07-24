package videoassets

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
)

const (
	MinLongEdge  = 1920
	MinShortEdge = 1080
)

type ProbeResult struct {
	Width    int
	Height   int
	Duration float64
}

type PosterPaths struct {
	Thumb   string
	Preview string
	Full    string
}

// MeetsMinimumResolution accepts both landscape 1920x1080 and portrait
// 1080x1920 videos while rejecting ultra-wide clips whose short edge is
// below 1080 pixels.
func MeetsMinimumResolution(width, height int) bool {
	if width <= 0 || height <= 0 {
		return false
	}
	longEdge, shortEdge := width, height
	if longEdge < shortEdge {
		longEdge, shortEdge = shortEdge, longEdge
	}
	return longEdge >= MinLongEdge && shortEdge >= MinShortEdge
}

func Probe(ctx context.Context, path string) (ProbeResult, error) {
	args := []string{
		"-v", "error",
		"-select_streams", "v:0",
		"-show_entries", "stream=width,height,duration:format=duration",
		"-print_format", "json",
		path,
	}
	out, err := exec.CommandContext(ctx, "ffprobe", args...).Output()
	if err != nil {
		return ProbeResult{}, fmt.Errorf("ffprobe: %w", err)
	}
	var parsed struct {
		Streams []struct {
			Width    int    `json:"width"`
			Height   int    `json:"height"`
			Duration string `json:"duration"`
		} `json:"streams"`
		Format struct {
			Duration string `json:"duration"`
		} `json:"format"`
	}
	if err := json.Unmarshal(out, &parsed); err != nil {
		return ProbeResult{}, fmt.Errorf("ffprobe parse: %w", err)
	}
	if len(parsed.Streams) == 0 {
		return ProbeResult{}, fmt.Errorf("ffprobe found no video streams")
	}
	result := ProbeResult{
		Width:  parsed.Streams[0].Width,
		Height: parsed.Streams[0].Height,
	}
	if duration, err := strconv.ParseFloat(parsed.Streams[0].Duration, 64); err == nil {
		result.Duration = duration
	} else if duration, err := strconv.ParseFloat(parsed.Format.Duration, 64); err == nil {
		result.Duration = duration
	}
	return result, nil
}

// Transcode normalizes the codec to H.264 + AAC without reducing resolution.
// yuv420p requires even dimensions, so an odd source edge is padded by one
// pixel instead of being scaled down.
func Transcode(ctx context.Context, inputPath, outputPath string) error {
	args := []string{
		"-y", "-hide_banner", "-loglevel", "error",
		"-i", inputPath,
		"-c:v", "libx264", "-profile:v", "high", "-preset", "medium", "-crf", "23",
		"-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2,format=yuv420p",
		"-pix_fmt", "yuv420p",
		"-c:a", "aac", "-b:a", "128k",
		"-movflags", "+faststart",
		"-max_muxing_queue_size", "1024",
		outputPath,
	}
	if out, err := exec.CommandContext(ctx, "ffmpeg", args...).CombinedOutput(); err != nil {
		return fmt.Errorf("ffmpeg transcode: %w (%s)", err, snippet(out, 400))
	}
	return nil
}

// GeneratePosters extracts the same frame into the three image tiers used by
// normal wallpapers: a 400x300-bounded thumb, a 1600px-wide preview, and a
// full-resolution poster. All outputs are WebP quality 80.
func GeneratePosters(ctx context.Context, videoPath string, duration float64, paths PosterPaths) error {
	seek := "1"
	if duration > 0 && duration < 1 {
		seek = "0"
	}
	outputs := []struct {
		path   string
		filter string
		label  string
	}{
		{paths.Thumb, "scale='min(400,iw)':'min(300,ih)':force_original_aspect_ratio=decrease", "thumb"},
		{paths.Preview, "scale='min(1600,iw)':-2", "preview"},
		{paths.Full, "null", "full poster"},
	}
	for _, output := range outputs {
		args := []string{
			"-y", "-hide_banner", "-loglevel", "error",
			"-ss", seek, "-i", videoPath,
			"-frames:v", "1",
			"-vf", output.filter,
			"-c:v", "libwebp", "-quality", "80",
			output.path,
		}
		if out, err := exec.CommandContext(ctx, "ffmpeg", args...).CombinedOutput(); err != nil {
			return fmt.Errorf("ffmpeg %s: %w (%s)", output.label, err, snippet(out, 400))
		}
	}
	return nil
}

func snippet(value []byte, limit int) string {
	value = bytes.TrimSpace(value)
	if len(value) <= limit {
		return string(value)
	}
	return strings.TrimSpace(string(value[:limit])) + "…"
}
