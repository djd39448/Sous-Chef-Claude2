// Tests for the server package. White-box (package server) so the test can
// reach into handleHealthz without standing up a TCP listener. The Handler
// path is exercised via httptest.NewRequestWithContext, so the full
// middleware chain (request id → access log → panic recovery) runs against
// each request — that's what makes /healthz a useful integration check.
package server

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/djd39448/Sous-Chef-Claude2/backend/internal/server/middleware"
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

// TestMiddlewareChain verifies the outermost-to-innermost order documented
// in withBaseMiddleware: panic recovery wraps request-id wraps access log
// wraps the mux. Reviewer-pass 0001 §3 flagged the lack of this test as a
// Should-fix; the assertions cover the two non-trivial invariants:
//
//   - A panic inside the access-log layer (which runs after request id is
//     attached) is recovered by the panic-recovery layer.
//   - The recovery log line carries the request id attached upstream — so
//     panic recovery (outermost) sees the context written by request id
//     (just inside it).
//   - The Content-Type and status of the recovered response match the
//     apierror.Internal envelope.
//
// One table; each row exercises one invariant. The handler is a tiny
// closure so the test is hermetic.
func TestMiddlewareChain(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name    string
		handler http.HandlerFunc
		assert  func(t *testing.T, rec *httptest.ResponseRecorder, logBuf *bytes.Buffer)
	}{
		{
			name: "request_id_in_access_log",
			handler: func(w http.ResponseWriter, r *http.Request) {
				// Read the request id from context; deeper handlers do
				// this to enrich their own logs. The middleware chain
				// must have attached one by this point.
				if id := middleware.RequestIDFromContext(r.Context()); id == "" {
					t.Error("inner handler saw an empty request id; the chain didn't attach one")
				}
				w.WriteHeader(http.StatusNoContent)
			},
			assert: func(t *testing.T, rec *httptest.ResponseRecorder, logBuf *bytes.Buffer) {
				t.Helper()
				if rec.Code != http.StatusNoContent {
					t.Errorf("status = %d, want 204", rec.Code)
				}
				if id := rec.Header().Get("X-Request-ID"); id == "" {
					t.Error("response missing X-Request-ID header")
				}
				if !strings.Contains(logBuf.String(), `"request_id"`) {
					t.Errorf("access log line missing request_id field: %s", logBuf.String())
				}
			},
		},
		{
			name: "panic_recovered_and_envelope_written",
			handler: func(_ http.ResponseWriter, _ *http.Request) {
				panic("invariant violated for test")
			},
			assert: func(t *testing.T, rec *httptest.ResponseRecorder, logBuf *bytes.Buffer) {
				t.Helper()
				if rec.Code != http.StatusInternalServerError {
					t.Errorf("status = %d, want 500 after panic recovery", rec.Code)
				}
				if got := rec.Header().Get("Content-Type"); got != "application/json; charset=utf-8" {
					t.Errorf("Content-Type = %q, want JSON", got)
				}
				var body map[string]any
				if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
					t.Fatalf("decoding body: %v", err)
				}
				if got, want := body["error"], "internal_error"; got != want {
					t.Errorf("error = %v, want %q (panic must produce contract §3.5 envelope)", got, want)
				}
				if !strings.Contains(logBuf.String(), "panic recovered") {
					t.Errorf("panic recovery log line missing: %s", logBuf.String())
				}
				if !strings.Contains(logBuf.String(), `"request_id"`) {
					t.Errorf("panic recovery log line missing request_id: %s", logBuf.String())
				}
			},
		},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			logBuf := &bytes.Buffer{}
			logger := slog.New(slog.NewJSONHandler(logBuf, &slog.HandlerOptions{Level: slog.LevelDebug}))

			srv, err := New(logger)
			if err != nil {
				t.Fatalf("New: %v", err)
			}
			// Mount the test handler under an arbitrary path with the
			// full middleware chain by going through Handler.
			mux := http.NewServeMux()
			mux.Handle("GET /test", c.handler)
			h := srv.withBaseMiddleware(mux)

			rec := httptest.NewRecorder()
			req := httptest.NewRequestWithContext(context.Background(), http.MethodGet, "/test", nil)
			h.ServeHTTP(rec, req)

			c.assert(t, rec, logBuf)
		})
	}
}
