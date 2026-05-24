// Tests for the server package. White-box (package server) so the test can
// reach into handleHealthz without standing up a TCP listener. The Handler
// path is exercised via httptest.NewRequestWithContext, so the full
// middleware chain (request id → access log → panic recovery) runs against
// each request — that's what makes /healthz a useful integration check.
package server

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
)

// newSilentServer builds a Server whose logger discards every line, so test
// output is not polluted by access-log entries from each request.
func newSilentServer(t *testing.T) *Server {
	t.Helper()
	logger := slog.New(slog.NewJSONHandler(io.Discard, nil))
	srv, err := New(logger)
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	return srv
}

func TestNewRejectsNilLogger(t *testing.T) {
	t.Parallel()
	if _, err := New(nil); err == nil {
		t.Fatal("New accepted nil logger, want an error")
	}
}

func TestHealthzReturnsContractShape(t *testing.T) {
	t.Parallel()
	srv := newSilentServer(t)

	rec := httptest.NewRecorder()
	req := httptest.NewRequestWithContext(context.Background(), http.MethodGet, "/healthz", nil)
	srv.Handler().ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("GET /healthz: status %d, want 200 (body=%q)", rec.Code, rec.Body.String())
	}

	contentType := rec.Header().Get("Content-Type")
	if contentType != "application/json; charset=utf-8" {
		t.Errorf("Content-Type = %q, want JSON", contentType)
	}

	// Per contract §3.6, the body MUST include {"status":"ok"}. Version and
	// BuildTime are optional diagnostic fields.
	var body healthzResponse
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatalf("decoding /healthz body: %v", err)
	}
	if body.Status != "ok" {
		t.Errorf("status = %q, want %q", body.Status, "ok")
	}
}

func TestHealthzPropagatesRequestID(t *testing.T) {
	t.Parallel()
	srv := newSilentServer(t)

	const inbound = "test-request-id-12345"
	rec := httptest.NewRecorder()
	req := httptest.NewRequestWithContext(context.Background(), http.MethodGet, "/healthz", nil)
	req.Header.Set("X-Request-ID", inbound)
	srv.Handler().ServeHTTP(rec, req)

	if got := rec.Header().Get("X-Request-ID"); got != inbound {
		t.Errorf("X-Request-ID = %q, want %q (the inbound id must be preserved)", got, inbound)
	}
}

func TestUnknownRouteReturns404(t *testing.T) {
	t.Parallel()
	srv := newSilentServer(t)

	rec := httptest.NewRecorder()
	req := httptest.NewRequestWithContext(context.Background(), http.MethodGet, "/no-such-route", nil)
	srv.Handler().ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("GET /no-such-route: status %d, want 404", rec.Code)
	}
}
