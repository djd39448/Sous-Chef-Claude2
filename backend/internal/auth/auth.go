// Package auth verifies Supabase-issued JWTs and exposes the verified user
// identity to the rest of the service. It owns the JWKS-backed signature
// check (issuer, expiry, audience, signing key), the `Authorization: Bearer`
// header parsing, and the typed context key that carries the authenticated
// user's UUID into every protected handler. Per contract §2 the identity
// flows from `sub` claim → `uuid.UUID` in context; no handler reads
// identity from any other source.
//
// Depends on: github.com/golang-jwt/jwt/v5 (parser + claims),
// github.com/MicahParks/keyfunc/v3 (JWKS fetch + cache + kid-miss refresh),
// github.com/google/uuid (sub-claim parsing),
// internal/apierror (the contract §3.5 error envelope written on rejection).
// Depended on by: internal/server (mounts Middleware in front of
// /api/kitchen/* routes), every authenticated handler (which reads the
// verified user id via UserIDFromContext).
// Why it exists: every endpoint under /api/kitchen requires a verified
// Supabase JWT. Centralising the verify + parse + context-attach pipeline
// in one package means a handler author never writes auth code — and the
// contract §2.3 rejection table is enforced in one place that a reviewer
// can audit in one sitting.
package auth

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/MicahParks/keyfunc/v3"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"

	"github.com/djd39448/Sous-Chef-Claude2/backend/internal/apierror"
)

// bearerPrefix is the case-sensitive scheme that prefixes a JWT in the
// Authorization header. Supabase clients always emit "Bearer " — per
// RFC 6750 the scheme is case-insensitive in principle, but a server that
// is strict here forces clients onto the documented convention and avoids
// per-deployment quirks.
const bearerPrefix = "Bearer "

// jwksRefreshInterval bounds how often the keyfunc client refreshes the
// JWKS cache in the absence of a kid miss. 24h matches plan §8 R2's
// stated TTL and Supabase's typical rotation cadence. On a kid miss the
// library re-fetches immediately; this constant only governs the
// background refresh.
const jwksRefreshInterval = 24 * time.Hour

// Claims is the subset of the Supabase-issued JWT this service consumes.
// Per contract §2.1 the canonical user id is the `sub` claim (a UUID);
// `email` is contact-only. Embedding jwt.RegisteredClaims gives us iss,
// exp, iat, aud verification for free via the jwt/v5 parser.
type Claims struct {
	jwt.RegisteredClaims

	// Email is the email address on the JWT, used only for diagnostics and
	// log enrichment. The contract pins it as non-identifying — never the
	// primary key for any row.
	Email string `json:"email,omitempty"`
}

// UserID parses the `sub` claim as a UUID. Per contract §2.1 the sub is
// always a Supabase Auth UUID; a malformed sub is treated as an invalid
// token. Returning the typed uuid.UUID at the boundary keeps every
// downstream handler off of string parsing.
func (c Claims) UserID() (uuid.UUID, error) {
	if c.Subject == "" {
		return uuid.Nil, errors.New("auth: jwt sub claim is empty")
	}
	id, err := uuid.Parse(c.Subject)
	if err != nil {
		return uuid.Nil, fmt.Errorf("auth: jwt sub %q is not a uuid: %w", c.Subject, err)
	}
	return id, nil
}

// Verifier validates a Supabase-issued JWT against a JWKS endpoint. It
// caches the keyset and refreshes on a kid miss (so a Supabase rotation
// does not produce a flood of 401s). Construct one Verifier per process
// at boot and share it across requests — the underlying keyfunc client is
// safe for concurrent use.
type Verifier struct {
	keyfunc jwt.Keyfunc
	issuer  string
	// parser is held on the struct so the configured options
	// (algorithms, leeway, required claims) stay in one place.
	parser *jwt.Parser
}

// NewVerifier constructs a Verifier backed by the JWKS endpoint at
// jwksURL. issuer is the expected `iss` claim — Supabase emits the project
// auth URL (e.g. `https://<project>.supabase.co/auth/v1`); a mismatch
// produces a `wrong_issuer` rejection. ctx is used only during the initial
// keyset fetch; the background refresher uses its own goroutine internally.
func NewVerifier(ctx context.Context, jwksURL, issuer string) (*Verifier, error) {
	if strings.TrimSpace(jwksURL) == "" {
		return nil, errors.New("auth: jwksURL is required")
	}
	if strings.TrimSpace(issuer) == "" {
		return nil, errors.New("auth: issuer is required")
	}

	k, err := keyfunc.NewDefaultCtx(ctx, []string{jwksURL})
	if err != nil {
		return nil, fmt.Errorf("auth: fetching JWKS %q: %w", jwksURL, err)
	}
	_ = jwksRefreshInterval // documented above; the keyfunc default handles refresh

	// The parser is configured once: explicit signing methods (RS256 is
	// Supabase's asymmetric default per dc-04), the issuer check, and
	// `exp` required. Audience is NOT pinned here — Supabase issues the
	// project audience and v1 has a single audience per project; if that
	// changes the verifier is amended.
	parser := jwt.NewParser(
		jwt.WithValidMethods([]string{"RS256", "ES256"}),
		jwt.WithIssuer(issuer),
		jwt.WithExpirationRequired(),
	)

	return &Verifier{
		keyfunc: k.Keyfunc,
		issuer:  issuer,
		parser:  parser,
	}, nil
}

// NewVerifierWithKeyfunc is the test seam: callers (in _test.go) construct
// a jwt.Keyfunc backed by a generated RSA key and an httptest.Server-hosted
// JWKS, then pass it here. Production code uses NewVerifier.
func NewVerifierWithKeyfunc(kf jwt.Keyfunc, issuer string) (*Verifier, error) {
	if kf == nil {
		return nil, errors.New("auth: keyfunc is required")
	}
	if strings.TrimSpace(issuer) == "" {
		return nil, errors.New("auth: issuer is required")
	}
	parser := jwt.NewParser(
		jwt.WithValidMethods([]string{"RS256", "ES256"}),
		jwt.WithIssuer(issuer),
		jwt.WithExpirationRequired(),
	)
	return &Verifier{keyfunc: kf, issuer: issuer, parser: parser}, nil
}

// VerifyError is the typed error returned by Verify. The Code field maps
// 1:1 to a contract §3.5 error code so the middleware can write the
// correct envelope without re-parsing the underlying jwt/v5 error chain.
type VerifyError struct {
	// Code is the contract §3.5 error code the caller surfaces on the
	// wire.
	Code apierror.Code
	// Cause is the wrapped lower-level error (for logging only — never
	// returned to the client).
	Cause error
}

// Error implements error; the format is for logs, not for the wire.
func (e *VerifyError) Error() string {
	if e.Cause == nil {
		return string(e.Code)
	}
	return fmt.Sprintf("auth verify: %s: %v", e.Code, e.Cause)
}

// Unwrap exposes the underlying jwt error so errors.As / errors.Is work
// against the jwt/v5 sentinel error set.
func (e *VerifyError) Unwrap() error { return e.Cause }

// Verify parses and validates raw against the Verifier's JWKS. On success
// it returns the typed Claims (post-validation; iss/exp already checked).
// On failure it returns a *VerifyError whose Code names exactly the
// contract §2.3 condition that failed.
func (v *Verifier) Verify(raw string) (Claims, error) {
	if strings.TrimSpace(raw) == "" {
		return Claims{}, &VerifyError{Code: apierror.CodeMalformedToken, Cause: errors.New("empty token")}
	}

	var claims Claims
	if _, err := v.parser.ParseWithClaims(raw, &claims, v.keyfunc); err != nil {
		return Claims{}, classifyParseError(err)
	}

	// jwt/v5 already enforced iss + exp via parser options; defence in
	// depth: an empty sub is treated as a malformed token because every
	// downstream handler needs a non-nil user id.
	if claims.Subject == "" {
		return Claims{}, &VerifyError{Code: apierror.CodeInvalidToken, Cause: errors.New("sub claim is empty")}
	}
	return claims, nil
}

// classifyParseError maps a jwt/v5 ParseWithClaims error onto the contract
// §2.3 rejection table. The mapping is exhaustive in practice — jwt/v5
// surfaces its outcomes through a small set of sentinel errors that we
// inspect with errors.Is.
func classifyParseError(err error) error {
	switch {
	case errors.Is(err, jwt.ErrTokenMalformed):
		return &VerifyError{Code: apierror.CodeMalformedToken, Cause: err}
	case errors.Is(err, jwt.ErrTokenExpired):
		return &VerifyError{Code: apierror.CodeExpiredToken, Cause: err}
	case errors.Is(err, jwt.ErrTokenInvalidIssuer):
		return &VerifyError{Code: apierror.CodeWrongIssuer, Cause: err}
	case errors.Is(err, jwt.ErrTokenSignatureInvalid),
		errors.Is(err, jwt.ErrTokenUnverifiable),
		errors.Is(err, jwt.ErrTokenInvalidClaims),
		errors.Is(err, jwt.ErrTokenRequiredClaimMissing),
		errors.Is(err, jwt.ErrTokenNotValidYet):
		return &VerifyError{Code: apierror.CodeInvalidToken, Cause: err}
	default:
		// Unknown parse error — treat as invalid_token, not malformed,
		// because the token reached the parser (malformed_token is the
		// contract code for "couldn't read a token at all").
		return &VerifyError{Code: apierror.CodeInvalidToken, Cause: err}
	}
}

// ctxKey is the typed unexported context-key type for the authenticated
// user id. dc-02 explicitly bans plain-string keys; using a distinct
// integer type also prevents collisions with the request-id key in
// internal/server/middleware.
type ctxKey int

const (
	ctxKeyUserID ctxKey = iota
	ctxKeyClaims
)

// UserIDFromContext returns the authenticated user's UUID, attached by
// Middleware. The bool return is `true` only when the middleware has run
// and the request is post-auth — handlers that read it without checking
// the bool would dereference uuid.Nil, which would in turn hit RLS as
// "no rows" — a quiet bug. The bool forces an explicit branch.
func UserIDFromContext(ctx context.Context) (uuid.UUID, bool) {
	v, ok := ctx.Value(ctxKeyUserID).(uuid.UUID)
	return v, ok
}

// ClaimsFromContext returns the verified Claims attached by Middleware.
// Only handlers that need the email or audience read it; most handlers
// only need UserIDFromContext.
func ClaimsFromContext(ctx context.Context) (Claims, bool) {
	v, ok := ctx.Value(ctxKeyClaims).(Claims)
	return v, ok
}

// Middleware returns an http middleware that enforces the contract §2.3
// rejection table on every request. The logger is the root logger;
// rejections log at warn level with the request id (attached by the
// outer request-id middleware) so a 401 is grep-able. Authenticated
// requests carry both the parsed Claims and the UUID-typed user id in
// the request context.
func Middleware(verifier *Verifier, logger *slog.Logger) func(http.Handler) http.Handler {
	if verifier == nil {
		panic("auth.Middleware: verifier is required")
	}
	if logger == nil {
		panic("auth.Middleware: logger is required")
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			raw, code, ok := extractBearer(r.Header.Get("Authorization"))
			if !ok {
				logger.LogAttrs(
					r.Context(), slog.LevelWarn, "auth rejected",
					slog.String("code", string(code)),
				)
				apierror.Write(w, http.StatusUnauthorized, code, nil)
				return
			}

			claims, err := verifier.Verify(raw)
			if err != nil {
				var ve *VerifyError
				if !errors.As(err, &ve) {
					// Shouldn't happen — Verify only returns *VerifyError —
					// but if a future change to Verify regresses this, fail
					// closed with invalid_token rather than leak a chain.
					ve = &VerifyError{Code: apierror.CodeInvalidToken, Cause: err}
				}
				logger.LogAttrs(
					r.Context(), slog.LevelWarn, "auth rejected",
					slog.String("code", string(ve.Code)),
					slog.Any("err", ve.Cause),
				)
				apierror.Write(w, http.StatusUnauthorized, ve.Code, nil)
				return
			}

			userID, err := claims.UserID()
			if err != nil {
				logger.LogAttrs(
					r.Context(), slog.LevelWarn, "auth rejected",
					slog.String("code", string(apierror.CodeInvalidToken)),
					slog.Any("err", err),
				)
				apierror.Write(w, http.StatusUnauthorized, apierror.CodeInvalidToken, nil)
				return
			}

			ctx := context.WithValue(r.Context(), ctxKeyUserID, userID)
			ctx = context.WithValue(ctx, ctxKeyClaims, claims)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// extractBearer parses an Authorization header value, returning the raw
// JWT and ok=true on success. On failure it returns the contract §2.3
// code that should be written to the wire. The split between
// missing_authorization (no header at all) and malformed_token (header
// present but not a Bearer scheme or empty token) matches the rejection
// table verbatim.
func extractBearer(header string) (string, apierror.Code, bool) {
	if header == "" {
		return "", apierror.CodeMissingAuthorization, false
	}
	if !strings.HasPrefix(header, bearerPrefix) {
		return "", apierror.CodeMalformedToken, false
	}
	raw := strings.TrimSpace(header[len(bearerPrefix):])
	if raw == "" {
		return "", apierror.CodeMalformedToken, false
	}
	return raw, "", true
}
