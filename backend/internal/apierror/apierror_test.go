// Tests for the error-envelope writer. The wire shape is normative
// (contract §3.5); these tests fail if the JSON keys, the omitempty
// behavior of `details`, or the status mapping ever drift.

package apierror_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/djd39448/Sous-Chef-Claude2/backend/internal/apierror"
)

func TestWrite_ShapeWithoutDetails(t *testing.T) {
	t.Parallel()

	rec := httptest.NewRecorder()
	apierror.Write(rec, http.StatusUnauthorized, apierror.CodeInvalidToken, nil)

	if got := rec.Code; got != http.StatusUnauthorized {
		t.Errorf("status: got %d, want %d", got, http.StatusUnauthorized)
	}
	if got := rec.Header().Get("Content-Type"); got != "application/json; charset=utf-8" {
		t.Errorf("Content-Type: got %q", got)
	}

	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decoding body: %v", err)
	}
	if got, want := body["error"], "invalid_token"; got != want {
		t.Errorf("error field: got %v, want %q", got, want)
	}
	if _, present := body["details"]; present {
		t.Errorf("details should be omitted when nil; body=%v", body)
	}
}

func TestWrite_ShapeWithDetails(t *testing.T) {
	t.Parallel()

	rec := httptest.NewRecorder()
	apierror.Write(rec, http.StatusBadRequest, apierror.CodeUnknownField, map[string]string{
		"field": "weekStartDate",
	})

	if got := rec.Code; got != http.StatusBadRequest {
		t.Errorf("status: got %d, want %d", got, http.StatusBadRequest)
	}

	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decoding body: %v", err)
	}
	if got, want := body["error"], "unknown_field"; got != want {
		t.Errorf("error field: got %v, want %q", got, want)
	}
	details, ok := body["details"].(map[string]any)
	if !ok {
		t.Fatalf("details should be an object; got %T", body["details"])
	}
	if got, want := details["field"], "weekStartDate"; got != want {
		t.Errorf("details.field: got %v, want %q", got, want)
	}
}

func TestInternal_AlwaysOpaque(t *testing.T) {
	t.Parallel()

	rec := httptest.NewRecorder()
	apierror.Internal(rec)

	if got := rec.Code; got != http.StatusInternalServerError {
		t.Errorf("status: got %d, want %d", got, http.StatusInternalServerError)
	}

	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decoding body: %v", err)
	}
	if got, want := body["error"], "internal_error"; got != want {
		t.Errorf("error: got %v, want %q", got, want)
	}
	if _, present := body["details"]; present {
		t.Error("details must be absent from an internal_error response (dc-02: no internal leak)")
	}
}

// TestCodes_AllExpectedConstants enumerates the codes from contract §3.5 so
// a future deletion or rename is caught at test time, not at a failing
// client integration.
func TestCodes_AllExpectedConstants(t *testing.T) {
	t.Parallel()

	expected := []apierror.Code{
		apierror.CodeMissingAuthorization,
		apierror.CodeMalformedToken,
		apierror.CodeInvalidToken,
		apierror.CodeExpiredToken,
		apierror.CodeWrongIssuer,
		apierror.CodeNotOwner,
		apierror.CodeNotFound,
		apierror.CodeUnknownField,
		apierror.CodeMissingField,
		apierror.CodeInvalidField,
		apierror.CodeWeekStartNotMonday,
		apierror.CodeEmptyTitle,
		apierror.CodeEmptyContent,
		apierror.CodeAIProviderError,
		apierror.CodeInternalError,
	}
	seen := make(map[apierror.Code]struct{}, len(expected))
	for _, c := range expected {
		if c == "" {
			t.Error("a Code constant is empty — contract §3.5 codes must be snake_case strings")
		}
		if _, dup := seen[c]; dup {
			t.Errorf("Code %q is duplicated in the constant set", c)
		}
		seen[c] = struct{}{}
	}
}
