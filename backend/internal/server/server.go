// Package server constructs the HTTP surface of the sous-chef-api binary.
// It owns the route mux, the middleware chain (request ID, slog logging,
// panic recovery, JWT auth), and the unauthenticated /healthz endpoint.
// Resource handlers (conversations, meal plans, cookbook, etc.) live in
// internal/api and are mounted onto the authenticated sub-mux exposed by
// MountAuth — server does not contain business logic.
//
// Depends on: internal/buildinfo (the /healthz response surface),
// internal/server/middleware (the request-ID, access-log, and panic-
// recovery chain), internal/auth (the JWT verifier and middleware),
// log/slog (the request-scoped logger).
// Depended on by: cmd/sous-chef-api, which constructs a *Server at boot
// and calls Serve to block until shutdown.
// Why it exists: the HTTP plumbing — listener lifecycle, signal handling,
// per-request middleware — is uninteresting to feature work but easy to get
// wrong. Isolating it here means a handler author writes only the handler.
package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"time"

	"github.com/djd39448/Sous-Chef-Claude2/backend/internal/auth"
	"github.com/djd39448/Sous-Chef-Claude2/backend/internal/buildinfo"
	"github.com/djd39448/Sous-Chef-Claude2/backend/internal/server/middleware"
)

// Timeouts on the http.Server. Read/write timeouts must be larger than the
// longest legitimate request the API ever services — chat SSE streams can
// be minutes long (contract §6.4 doesn't specify, but the source's chat
// sessions can run several minutes), so the write timeout is generous. The
// read timeout is the inverse: a client opening a chat session sends a
// small POST body and then reads, so a 30s read timeout is plenty.
const (
	readHeaderTimeout = 5 * time.Second
	readTimeout       = 30 * time.Second
	writeTimeout      = 10 * time.Minute
	idleTimeout       = 60 * time.Second
	shutdownGrace     = 15 * time.Second
)

// Server is the wired-together HTTP service. It is constructed once at boot
// and serves until its context is cancelled. The verifier and authRoutes
// fields are optional at construction so a foundation-only deploy (Phase A)
// still boots; from Phase B onwards every production boot supplies both.
type Server struct {
	logger     *slog.Logger
	verifier   *auth.Verifier
	authRoutes []authRoute
}

// authRoute is one method+path+handler triple destined for the
// JWT-protected sub-mux. The slice is held on the Server and registered
// when Handler() runs so MountAuth callers do not have to worry about
// ordering relative to the handler construction.
type authRoute struct {
	pattern string
	handler http.Handler
}

// New builds a Server with the given logger. The logger is the root of the
// request-scoped logging tree — every request derives a child logger that
// attaches `request_id` (and, post-auth, `user_id`). A nil logger is
// rejected at construction time because the entire service depends on it.
//
// The optional opts let main.go inject a JWT verifier (per contract §2.2
// + ADR-0011); without one no /api/kitchen route can be mounted. The
// verifier MAY be nil in tests that only exercise /healthz.
func New(logger *slog.Logger, opts ...Option) (*Server, error) {
	if logger == nil {
		return nil, errors.New("server.New: logger is required")
	}
	s := &Server{logger: logger}
	for _, opt := range opts {
		opt(s)
	}
	return s, nil
}

// Option is a server construction option. Functional options keep the
// signature stable as later phases add the data pool, the AI client, etc.
type Option func(*Server)

// WithVerifier installs the JWT verifier used by the auth middleware on
// every /api/kitchen/* route. Required for any production boot; tests that
// only need /healthz can omit it.
func WithVerifier(v *auth.Verifier) Option {
	return func(s *Server) { s.verifier = v }
}

// MountAuth registers a handler under the JWT-protected sub-mux. The
// pattern follows the ServeMux 1.22+ method+path syntax (`"GET
// /api/kitchen/ingredients"`). Calling MountAuth after Handler() has been
// called is allowed but only takes effect on the NEXT Handler() call —
// tests that mount routes inline must call Handler() last.
func (s *Server) MountAuth(pattern string, handler http.Handler) {
	s.authRoutes = append(s.authRoutes, authRoute{pattern: pattern, handler: handler})
}

// Handler returns the http.Handler with every route mounted and the
// middleware chain composed. Calling it more than once is allowed and
// returns equivalent handlers — useful in tests where ServeMux behavior is
// inspected without going through Serve.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()

	// /healthz is registered before middleware so the load balancer's
	// health probe is the cheapest possible response. The probe runs every
	// few seconds; threading a request through five layers of middleware
	// to return `{"status":"ok"}` would be wasted work.
	mux.HandleFunc("GET /healthz", s.handleHealthz)

	// Authenticated routes share a sub-mux behind the JWT middleware. The
	// sub-mux uses the same ServeMux 1.22+ method+path patterns; the auth
	// middleware wraps the *whole* sub-mux, so a contract §2.3 401 is
	// emitted before any handler runs.
	if len(s.authRoutes) > 0 {
		authMux := http.NewServeMux()
		for _, r := range s.authRoutes {
			authMux.Handle(r.pattern, r.handler)
		}
		if s.verifier == nil {
			// dc-02: a misconfigured boot must fail loudly. Returning a
			// 500-handler from Handler() would let the binary serve
			// /healthz green while every protected route silently 500s,
			// which would mask the configuration bug. Panic at
			// Handler-construction time instead — main.go calls Handler
			// once at boot, so this surfaces inside the run() function's
			// error return path.
			panic("server: MountAuth called without WithVerifier")
		}
		mux.Handle("/api/kitchen/", auth.Middleware(s.verifier, s.logger)(authMux))
	}

	return s.withBaseMiddleware(mux)
}

// withBaseMiddleware composes the always-on middleware chain. Order is
// outermost-to-innermost as the code reads, which matches the runtime
// order. Recovery is outermost so it catches a panic from any inner layer;
// request-ID generation is next so the recovery log carries the request id;
// access logging is innermost so the logged status reflects every layer.
func (s *Server) withBaseMiddleware(next http.Handler) http.Handler {
	chain := middleware.WithAccessLog(s.logger, next)
	chain = middleware.WithRequestID(chain)
	chain = middleware.WithPanicRecovery(s.logger, chain)
	return chain
}

// healthzResponse is the wire shape of GET /healthz. Per contract §3.6 the
// body is `{"status":"ok"}`. The version and build-time fields are added as
// optional diagnostics — a load balancer ignores them, an operator running
// `curl /healthz` gets the running build's identity for free.
type healthzResponse struct {
	Status    string `json:"status"`
	Version   string `json:"version,omitempty"`
	BuildTime string `json:"buildTime,omitempty"`
}

// handleHealthz answers GET /healthz with the contract §3.6 shape. The
// endpoint is unauthenticated, has no dependencies (no DB ping yet — that
// lands in Phase C1), and is safe for the load balancer to call at any
// frequency.
func (s *Server) handleHealthz(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	// Expose the build identity to operators as a header too; an SRE
	// running `curl -I` against /healthz sees which build is answering
	// without needing to parse the body.
	w.Header().Set("X-Build-Version", buildinfo.Version)

	if err := json.NewEncoder(w).Encode(healthzResponse{
		Status:    "ok",
		Version:   buildinfo.Version,
		BuildTime: buildinfo.BuildTime,
	}); err != nil {
		// Headers are already on the wire; logging is the only remaining
		// signal. /healthz writes ~80 bytes — failure here means the
		// client hung up, not that we ran out of buffer.
		s.logger.Error("healthz encode", slog.Any("err", err))
	}
}

// Serve runs the HTTP server on ln until ctx is cancelled, then drains
// inflight requests with a bounded grace period. The caller owns ln (so
// port-0 selection stays in cmd/sous-chef-api) and ctx (so signal handling
// stays in main). This split mirrors internal/apiserver in DevCore — main
// holds lifecycle, server holds protocol.
func (s *Server) Serve(ctx context.Context, ln net.Listener) error {
	srv := &http.Server{
		Handler:           s.Handler(),
		ReadHeaderTimeout: readHeaderTimeout,
		ReadTimeout:       readTimeout,
		WriteTimeout:      writeTimeout,
		IdleTimeout:       idleTimeout,
	}

	errCh := make(chan error, 1)
	go func() {
		err := srv.Serve(ln)
		if errors.Is(err, http.ErrServerClosed) {
			errCh <- nil
			return
		}
		errCh <- err
	}()

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
		// A fresh context for Shutdown — the parent ctx is already cancelled,
		// so passing it would tell Shutdown to abort immediately rather than
		// wait for inflight requests.
		shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownGrace)
		defer cancel()
		if err := srv.Shutdown(shutdownCtx); err != nil { //nolint:contextcheck // independent shutdown deadline by design
			return fmt.Errorf("shutting down http server: %w", err)
		}
		return nil
	}
}
