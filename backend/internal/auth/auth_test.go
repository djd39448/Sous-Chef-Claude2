// Tests for the auth package. Black-box (package auth_test) so the test
// exercises only the exported surface — Verifier construction, Verify on a
// signed token, Middleware on a real http.Handler chain. Signing keys are
// generated per test run so no key material is committed to the repo.
//
// Coverage maps to the contract §2.3 rejection table:
//   - missing Authorization header → 401 missing_authorization
//   - malformed Authorization header → 401 malformed_token
//   - token signed by wrong key → 401 invalid_token
//   - expired token → 401 expired_token
//   - wrong issuer → 401 wrong_issuer
//   - valid token → 200 + UserIDFromContext returns the sub UUID
package auth_test

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"math/big"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"

	"github.com/djd39448/Sous-Chef-Claude2/backend/internal/apierror"
	"github.com/djd39448/Sous-Chef-Claude2/backend/internal/auth"
)

// testIssuer is the iss claim every well-formed test JWT carries. Matches
// Supabase's project-prefixed URL convention from contract §2.2.
const testIssuer = "https://test-project.supabase.co/auth/v1"

// silentLogger discards all log output so the test runner stays readable;
// the auth middleware logs at warn on every rejection, which would
// otherwise flood `go test -v`.
func silentLogger() *slog.Logger {
	return slog.New(slog.NewJSONHandler(io.Discard, nil))
}

// signingFixture is the per-test cryptographic context: a freshly generated
// RSA key (so no key material is ever committed) and a Keyfunc that
// resolves to its public counterpart.
type signingFixture struct {
	keyID    string
	priv     *rsa.PrivateKey
	verifier *auth.Verifier
}

// newSigningFixture generates an RSA key, builds a jwt.Keyfunc that returns
// the corresponding public key for any kid, and constructs a Verifier
// configured for testIssuer. Tests sign tokens with fix.priv and verify
// through fix.verifier.
func newSigningFixture(t *testing.T) *signingFixture {
	t.Helper()
	priv, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("rsa.GenerateKey: %v", err)
	}
	kid := "test-kid-" + uuid.NewString()

	kf := func(token *jwt.Token) (any, error) {
		// Honour the kid in the header in case a future test exercises
		// multi-key rotation; for now there is only one key.
		if got := token.Header["kid"]; got != nil && got != kid {
			return nil, jwt.ErrTokenUnverifiable
		}
		return &priv.PublicKey, nil
	}
	v, err := auth.NewVerifierWithKeyfunc(kf, testIssuer)
	if err != nil {
		t.Fatalf("NewVerifierWithKeyfunc: %v", err)
	}
	return &signingFixture{keyID: kid, priv: priv, verifier: v}
}

// signClaims returns a Bearer-ready string signed with fix.priv. mutate is
// invoked on the claims after sensible defaults are filled, so a test can
// override iss, sub, exp, etc.
func (fix *signingFixture) signClaims(t *testing.T, mutate func(*auth.Claims)) string {
	t.Helper()
	now := time.Now()
	claims := &auth.Claims{
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    testIssuer,
			Subject:   uuid.NewString(),
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(time.Hour)),
		},
		Email: "user@example.test",
	}
	if mutate != nil {
		mutate(claims)
	}
	tok := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	tok.Header["kid"] = fix.keyID
	signed, err := tok.SignedString(fix.priv)
	if err != nil {
		t.Fatalf("SignedString: %v", err)
	}
	return signed
}

func TestNewVerifierRejectsEmptyArgs(t *testing.T) {
	t.Parallel()
	if _, err := auth.NewVerifierWithKeyfunc(nil, testIssuer); err == nil {
		t.Error("NewVerifierWithKeyfunc accepted a nil keyfunc")
	}
	kf := func(*jwt.Token) (any, error) { return nil, nil }
	if _, err := auth.NewVerifierWithKeyfunc(kf, "  "); err == nil {
		t.Error("NewVerifierWithKeyfunc accepted a blank issuer")
	}
}

func TestVerify_RejectsTamperedSignature(t *testing.T) {
	t.Parallel()
	fix := newSigningFixture(t)

	// Sign with a *different* key — the verifier's keyfunc holds the
	// fixture's public key, so this token's signature won't verify.
	other, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("rsa.GenerateKey: %v", err)
	}
	claims := &auth.Claims{
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    testIssuer,
			Subject:   uuid.NewString(),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour)),
		},
	}
	tok := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	tok.Header["kid"] = fix.keyID
	signed, err := tok.SignedString(other)
	if err != nil {
		t.Fatalf("SignedString: %v", err)
	}

	_, err = fix.verifier.Verify(signed)
	assertVerifyCode(t, err, apierror.CodeInvalidToken)
}

func TestVerify_RejectsExpired(t *testing.T) {
	t.Parallel()
	fix := newSigningFixture(t)
	tok := fix.signClaims(t, func(c *auth.Claims) {
		c.ExpiresAt = jwt.NewNumericDate(time.Now().Add(-time.Minute))
		c.IssuedAt = jwt.NewNumericDate(time.Now().Add(-time.Hour))
	})
	_, err := fix.verifier.Verify(tok)
	assertVerifyCode(t, err, apierror.CodeExpiredToken)
}

func TestVerify_RejectsWrongIssuer(t *testing.T) {
	t.Parallel()
	fix := newSigningFixture(t)
	tok := fix.signClaims(t, func(c *auth.Claims) {
		c.Issuer = "https://attacker.example/auth/v1"
	})
	_, err := fix.verifier.Verify(tok)
	assertVerifyCode(t, err, apierror.CodeWrongIssuer)
}

func TestVerify_RejectsMalformed(t *testing.T) {
	t.Parallel()
	fix := newSigningFixture(t)

	cases := []struct {
		name string
		raw  string
	}{
		{"empty", ""},
		{"whitespace", "   "},
		{"not-a-jwt", "definitely-not-a-jwt"},
		{"two-segments", "aaaa.bbbb"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			_, err := fix.verifier.Verify(tc.raw)
			if err == nil {
				t.Fatal("Verify accepted a malformed token")
			}
			// Malformed and empty both map to malformed_token per the
			// extractBearer path; from inside Verify the empty case is
			// also malformed_token (explicit guard in Verify).
			var ve *auth.VerifyError
			if !verifyErrorAs(err, &ve) {
				t.Fatalf("error %T not *auth.VerifyError", err)
			}
			if ve.Code != apierror.CodeMalformedToken && ve.Code != apierror.CodeInvalidToken {
				t.Errorf("code = %q, want malformed_token or invalid_token", ve.Code)
			}
		})
	}
}

func TestVerify_RejectsEmptySub(t *testing.T) {
	t.Parallel()
	fix := newSigningFixture(t)
	tok := fix.signClaims(t, func(c *auth.Claims) {
		c.Subject = ""
	})
	_, err := fix.verifier.Verify(tok)
	assertVerifyCode(t, err, apierror.CodeInvalidToken)
}

func TestVerify_AcceptsValidToken(t *testing.T) {
	t.Parallel()
	fix := newSigningFixture(t)
	expectSub := uuid.New()
	tok := fix.signClaims(t, func(c *auth.Claims) {
		c.Subject = expectSub.String()
	})
	claims, err := fix.verifier.Verify(tok)
	if err != nil {
		t.Fatalf("Verify: %v", err)
	}
	gotID, err := claims.UserID()
	if err != nil {
		t.Fatalf("UserID: %v", err)
	}
	if gotID != expectSub {
		t.Errorf("UserID = %s, want %s", gotID, expectSub)
	}
}

// TestMiddleware_RejectionTable maps contract §2.3 to wire behaviour.
// One subtest per row; each asserts the HTTP status, the JSON envelope's
// `error` field, and that the next handler did NOT run.
func TestMiddleware_RejectionTable(t *testing.T) {
	t.Parallel()
	fix := newSigningFixture(t)

	type tc struct {
		name       string
		authHeader string
		token      func(*testing.T) string
		wantCode   apierror.Code
	}
	tokWith := func(mut func(*auth.Claims)) func(*testing.T) string {
		return func(t *testing.T) string { return "Bearer " + fix.signClaims(t, mut) }
	}

	otherKey, _ := rsa.GenerateKey(rand.Reader, 2048)
	signWithOther := func(t *testing.T) string {
		t.Helper()
		claims := &auth.Claims{
			RegisteredClaims: jwt.RegisteredClaims{
				Issuer:    testIssuer,
				Subject:   uuid.NewString(),
				IssuedAt:  jwt.NewNumericDate(time.Now()),
				ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour)),
			},
		}
		tok := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
		tok.Header["kid"] = fix.keyID
		signed, err := tok.SignedString(otherKey)
		if err != nil {
			t.Fatalf("SignedString: %v", err)
		}
		return "Bearer " + signed
	}

	cases := []tc{
		{
			name:       "missing_header",
			authHeader: "",
			wantCode:   apierror.CodeMissingAuthorization,
		},
		{
			name:       "no_bearer_scheme",
			authHeader: "Basic Zm9vOmJhcg==",
			wantCode:   apierror.CodeMalformedToken,
		},
		{
			name:       "bearer_empty",
			authHeader: "Bearer    ",
			wantCode:   apierror.CodeMalformedToken,
		},
		{
			name:     "bearer_garbage",
			token:    func(*testing.T) string { return "Bearer not-a-jwt" },
			wantCode: apierror.CodeMalformedToken,
		},
		{
			name:     "expired",
			token:    tokWith(func(c *auth.Claims) { c.ExpiresAt = jwt.NewNumericDate(time.Now().Add(-time.Minute)) }),
			wantCode: apierror.CodeExpiredToken,
		},
		{
			name:     "wrong_issuer",
			token:    tokWith(func(c *auth.Claims) { c.Issuer = "https://attacker.example/auth/v1" }),
			wantCode: apierror.CodeWrongIssuer,
		},
		{
			name:     "wrong_signature",
			token:    signWithOther,
			wantCode: apierror.CodeInvalidToken,
		},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			calledNext := false
			next := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				calledNext = true
				w.WriteHeader(http.StatusOK)
			})

			h := auth.Middleware(fix.verifier, silentLogger())(next)

			req := httptest.NewRequestWithContext(context.Background(), http.MethodGet, "/api/kitchen/ingredients", nil)
			header := c.authHeader
			if c.token != nil {
				header = c.token(t)
			}
			if header != "" {
				req.Header.Set("Authorization", header)
			}
			rec := httptest.NewRecorder()
			h.ServeHTTP(rec, req)

			if calledNext {
				t.Error("middleware passed to next handler despite an auth failure")
			}
			if rec.Code != http.StatusUnauthorized {
				t.Errorf("status = %d, want 401 (body=%s)", rec.Code, rec.Body.String())
			}

			var env map[string]any
			if err := json.NewDecoder(rec.Body).Decode(&env); err != nil {
				t.Fatalf("decoding envelope: %v (body=%s)", err, rec.Body.String())
			}
			if got, want := env["error"], string(c.wantCode); got != want {
				t.Errorf("error code = %v, want %q", got, want)
			}
		})
	}
}

func TestMiddleware_PassesValidTokenAndAttachesContext(t *testing.T) {
	t.Parallel()
	fix := newSigningFixture(t)
	wantID := uuid.New()
	signed := fix.signClaims(t, func(c *auth.Claims) {
		c.Subject = wantID.String()
		c.Email = "valid@example.test"
	})

	var (
		sawUserID uuid.UUID
		sawOK     bool
		sawEmail  string
	)
	next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		sawUserID, sawOK = auth.UserIDFromContext(r.Context())
		if c, ok := auth.ClaimsFromContext(r.Context()); ok {
			sawEmail = c.Email
		}
		w.WriteHeader(http.StatusNoContent)
	})

	h := auth.Middleware(fix.verifier, silentLogger())(next)
	req := httptest.NewRequestWithContext(context.Background(), http.MethodGet, "/api/kitchen/ingredients", nil)
	req.Header.Set("Authorization", "Bearer "+signed)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)

	if rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204 (body=%s)", rec.Code, rec.Body.String())
	}
	if !sawOK {
		t.Fatal("UserIDFromContext returned ok=false on a valid request")
	}
	if sawUserID != wantID {
		t.Errorf("UserIDFromContext = %s, want %s", sawUserID, wantID)
	}
	if sawEmail != "valid@example.test" {
		t.Errorf("ClaimsFromContext().Email = %q, want %q", sawEmail, "valid@example.test")
	}
}

// TestNewVerifier_FromHTTPJWKS exercises the production constructor against
// a real httptest.Server serving a JWKS document. This confirms the
// keyfunc/v3 dependency wiring works end-to-end — the RSA key the test
// generates is published in JWK form, and a token signed with that key
// verifies through NewVerifier (not the test seam).
func TestNewVerifier_FromHTTPJWKS(t *testing.T) {
	t.Parallel()

	priv, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("rsa.GenerateKey: %v", err)
	}
	kid := "kid-http-1"

	jwksDoc := map[string]any{
		"keys": []map[string]any{{
			"kty": "RSA",
			"alg": "RS256",
			"use": "sig",
			"kid": kid,
			"n":   base64URLUint(priv.N),
			"e":   base64URLUint(big.NewInt(int64(priv.E))),
		}},
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(jwksDoc)
	}))
	t.Cleanup(srv.Close)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	verifier, err := auth.NewVerifier(ctx, srv.URL, testIssuer)
	if err != nil {
		t.Fatalf("NewVerifier: %v", err)
	}

	wantSub := uuid.New()
	claims := &auth.Claims{
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    testIssuer,
			Subject:   wantSub.String(),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour)),
		},
	}
	tok := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	tok.Header["kid"] = kid
	signed, err := tok.SignedString(priv)
	if err != nil {
		t.Fatalf("SignedString: %v", err)
	}

	got, err := verifier.Verify(signed)
	if err != nil {
		t.Fatalf("Verify (HTTP JWKS): %v", err)
	}
	gotID, err := got.UserID()
	if err != nil {
		t.Fatalf("UserID: %v", err)
	}
	if gotID != wantSub {
		t.Errorf("UserID = %s, want %s", gotID, wantSub)
	}
}

// base64URLUint encodes a positive big.Int as the URL-safe base64 (no
// padding) form RFC 7518 prescribes for JWK `n` and `e` values.
func base64URLUint(n *big.Int) string {
	b := n.Bytes()
	// Trim any leading zero byte that big.Int would not emit, but be
	// defensive: the spec disallows leading zero octets.
	for len(b) > 1 && b[0] == 0 {
		b = b[1:]
	}
	return base64.RawURLEncoding.EncodeToString(b)
}

// assertVerifyCode unwraps a *auth.VerifyError and asserts its Code field.
// Used by every Verify-level test so the assertion is one call.
func assertVerifyCode(t *testing.T, err error, want apierror.Code) {
	t.Helper()
	if err == nil {
		t.Fatalf("Verify: got nil error, want code %q", want)
	}
	var ve *auth.VerifyError
	if !verifyErrorAs(err, &ve) {
		t.Fatalf("error %T not *auth.VerifyError: %v", err, err)
	}
	if ve.Code != want {
		t.Errorf("code = %q, want %q (cause=%v)", ve.Code, want, ve.Cause)
	}
}

// verifyErrorAs is a small wrapper around errors.As scoped to the auth
// package's typed error. Kept as a helper so the assertion at each call
// site is one short line.
func verifyErrorAs(err error, target **auth.VerifyError) bool {
	return errors.As(err, target)
}
