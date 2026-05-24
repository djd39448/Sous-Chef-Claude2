// Package middleware holds the http.Handler decorators the server applies
// in front of every route: a request-ID assigner, an access logger, a panic
// recovery shield, and (in Phase B) the JWT auth verifier. Each decorator
// is one exported function taking a child handler and returning a wrapped
// handler — the standard Go middleware idiom.
//
// Depends on: internal/apierror (the panic-recovery response envelope),
// crypto/rand + encoding/hex (request-ID generation), log/slog (the access
// log writer).
// Depended on by: internal/server, which composes the middlewares into the
// outermost-to-innermost chain that wraps the mux.
// Why it exists: the middleware concerns are pure cross-cutting plumbing
// — a feature handler should never have to think about them. Keeping each
// concern in its own small function with its own test lets a Phase 4
// auditor confirm the chain is correct in minutes.
package middleware

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"log/slog"
	"net/http"
	"runtime/debug"
	"time"

	"github.com/djd39448/Sous-Chef-Claude2/backend/internal/apierror"
)

// requestIDLen is half the byte length of the random suffix portion of a
// request ID; the encoded hex is twice this. Sixteen hex chars (8 random
// bytes) is enough to avoid collisions across the lifetime of a request
// stream and short enough to read in a log scroll.
const requestIDLen = 8

// requestIDHeader is the HTTP header carrying the request id on both sides
// of the wire. The standard "X-Request-ID" is recognised by every log
// aggregator and proxy; using the same name preserves the id end-to-end
// when a client adds it on the outbound request.
const requestIDHeader = "X-Request-ID"

// ctxKey is the typed unexported context-key type used to attach
// request-scoped values. dc-02 explicitly bans plain-string keys.
type ctxKey int

const (
	ctxKeyRequestID ctxKey = iota
)

// WithRequestID attaches an X-Request-ID to every request, either honoring
// a caller-supplied id (a load balancer or an upstream service may have
// already issued one) or generating a fresh one. The id lands in the
// response header and in the request context so deeper layers can include
// it in their logs.
func WithRequestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get(requestIDHeader)
		if id == "" {
			id = newRequestID()
		}
		w.Header().Set(requestIDHeader, id)
		ctx := context.WithValue(r.Context(), ctxKeyRequestID, id)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// RequestIDFromContext returns the request id attached by WithRequestID, or
// the empty string if the middleware has not run. The empty-string return
// is deliberate: a logger that includes an empty `request_id` is a louder
// signal than a panic at log time would be.
func RequestIDFromContext(ctx context.Context) string {
	if v, ok := ctx.Value(ctxKeyRequestID).(string); ok {
		return v
	}
	return ""
}

// statusRecorder is a thin http.ResponseWriter wrapper that captures the
// status code as it is written, so the access logger can emit it. Only the
// status is recorded — the body passes through untouched, which matters
// for SSE responses (a buffering writer would break flushing).
type statusRecorder struct {
	http.ResponseWriter
	status int
}

// WriteHeader records the status before delegating. The default for a
// handler that never calls WriteHeader is 200, set in the constructor.
func (sr *statusRecorder) WriteHeader(code int) {
	sr.status = code
	sr.ResponseWriter.WriteHeader(code)
}

// Flush forwards to the wrapped ResponseWriter's Flush implementation when
// it exists. Without this passthrough, wrapping a Flusher-supporting
// writer would silently strip the capability — fatal for SSE.
func (sr *statusRecorder) Flush() {
	if f, ok := sr.ResponseWriter.(http.Flusher); ok {
		f.Flush()
	}
}

// WithAccessLog emits one structured log line per completed request,
// carrying the method, path, status, duration, and request id. The logger
// is the root logger; this middleware does not derive a child because the
// access log is a single event, not a per-request scope.
func WithAccessLog(logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sr := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(sr, r)
		logger.LogAttrs(
			r.Context(), slog.LevelInfo, "http request",
			slog.String("method", r.Method),
			slog.String("path", r.URL.Path),
			slog.Int("status", sr.status),
			slog.Duration("duration", time.Since(start)),
			slog.String("request_id", RequestIDFromContext(r.Context())),
		)
	})
}

// WithPanicRecovery catches a panic from any downstream handler, logs the
// stack at error level, and returns a contract §3.5 internal_error
// envelope. The recovered process keeps serving — dc-02 reserves panic
// for invariant violations, so a runtime panic is always a bug to be
// logged and contained, not allowed to kill the server.
//
// http.ErrAbortHandler is a special-cased sentinel — the stdlib uses it
// internally to abort a request without logging; we propagate that
// behavior rather than treating it as an error.
func WithPanicRecovery(logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			recovered := recover()
			if recovered == nil {
				return
			}
			if err, ok := recovered.(error); ok && errors.Is(err, http.ErrAbortHandler) {
				// Re-panic so the stdlib's own handling fires. This is the
				// stdlib's documented signal for "abort this request silently".
				panic(recovered)
			}
			logger.LogAttrs(
				r.Context(), slog.LevelError, "panic recovered",
				slog.Any("panic", recovered),
				slog.String("stack", string(debug.Stack())),
				slog.String("request_id", RequestIDFromContext(r.Context())),
			)
			apierror.Internal(w)
		}()
		next.ServeHTTP(w, r)
	})
}

// newRequestID returns a hex-encoded random id. crypto/rand is the source;
// a math/rand id would be guessable, which matters in a per-request
// identifier that may appear in client logs.
func newRequestID() string {
	buf := make([]byte, requestIDLen)
	if _, err := rand.Read(buf); err != nil {
		// crypto/rand.Read on every supported platform never fails in
		// practice; documenting the case keeps the error path explicit
		// rather than swallowed. Falling back to a time-based id keeps
		// the service answering rather than 500ing on this purely
		// cosmetic value.
		return "fallback-" + time.Now().UTC().Format("20060102T150405.000000000")
	}
	return hex.EncodeToString(buf)
}
