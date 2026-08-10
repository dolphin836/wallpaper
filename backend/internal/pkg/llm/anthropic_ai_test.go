package llm

import "testing"

func TestParseAIGenerationAssessmentNormalizesResponse(t *testing.T) {
	raw := "```json\n{\"is_ai_generated\":true,\"confidence\":1.4,\"notes\":\"  repeated melted texture  \"}\n```"
	got, err := parseAIGenerationAssessment(raw)
	if err != nil {
		t.Fatalf("parseAIGenerationAssessment() error = %v", err)
	}
	if !got.IsAIGenerated {
		t.Fatal("parseAIGenerationAssessment() is_ai_generated = false, want true")
	}
	if got.Confidence != 1 {
		t.Fatalf("parseAIGenerationAssessment() confidence = %v, want 1", got.Confidence)
	}
	if got.Notes != "repeated melted texture" {
		t.Fatalf("parseAIGenerationAssessment() notes = %q", got.Notes)
	}
}

func TestParseAIGenerationAssessmentRejectsEmptyResponse(t *testing.T) {
	if _, err := parseAIGenerationAssessment("  "); err == nil {
		t.Fatal("parseAIGenerationAssessment() error = nil, want error")
	}
}
