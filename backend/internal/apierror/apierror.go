// Package apierror is the single writer of error responses to the wire. It
// owns the response envelope from contract §3.5 — `{ "error": "<code>",
// "details": <any> }` — and the snake_case error codes enumerated there.
// Every handler that needs to reject a request calls into this package; no
// handler builds an error response by hand.
//
// Depends on: net/http, encoding/json, log/slog (standard library only —
// slog is used ONLY for the encoding-failure fallback in Write, never to
// log the contract-level error envelope itself; the caller logs that).
// Depended on by: every HTTP handler under internal/api, the auth
// middleware (internal/server/middleware), and the SSE writer (which needs
// to translate a typed terminal error into the `error` SSE event).
// Why it exists: scattered ad-hoc error responses break the contract over
// time. One package owning the envelope means the wire shape cannot drift
// — and the typed codes catch handler bugs at compile time rather than at a
// failing client integration test.
package apierror

import (
	"encoding/json"
	"log/slog"
	"net/http"
)

// Code is a typed alias for the wire-level error identifier. Defining it as
// a string subtype prevents a handler from passing an arbitrary literal —
// the compiler enforces that every code is one of the constants below or a
// per-handler extension declared with this type.
type Code string

// The codes from contract §3.5. Adding a new code requires an explicit edit
// here so the wire surface stays auditable. The grouping by comment block
// matches the contract's table layout.
const (
	// Auth — §2.3.
	CodeMissingAuthorization Code = "missing_authorization"
	CodeMalformedToken       Code = "malformed_token"
	CodeInvalidToken         Code = "invalid_token"
	CodeExpiredToken         Code = "expired_token"
	CodeWrongIssuer          Code = "wrong_issuer"

	// Resource access — §2.3.
	CodeNotOwner Code = "not_owner"
	CodeNotFound Code = "not_found"

	// Request validation — §3.5.
	CodeUnknownField Code = "unknown_field"
	CodeMissingField Code = "missing_field"
	CodeInvalidField Code = "invalid_field"

	// Date validation — §3.2.
	CodeWeekStartNotMonday Code = "week_start_not_monday"

	// Cookbook validation — §5.6.
	CodeEmptyTitle   Code = "empty_title"
	CodeEmptyContent Code = "empty_content"

	// Upstream / internal.
	CodeAIProviderError Code = "ai_provider_error"
	CodeInternalError   Code = "internal_error"
)

// envelope is the wire shape from contract §3.5. `Details` is `any` because
// the contract allows arbitrary structured context (field names, validation
// reasons, etc.) and `omitempty` keeps the wire clean when no details apply.
type envelope struct {
	Error   Code `json:"error"`
	Details any  `json:"details,omitempty"`
}

// Write serializes a contract-§3.5 error envelope and writes it to w with
// the given HTTP status. `details` is optional — pass nil to omit the field
// from the response. The Content-Type header is set before WriteHeader so
// the body is parseable as JSON by every client.
//
// On the **happy path**, Write does not log. The caller (a handler or
// middleware) holds the request-scoped slog.Logger and the wrapped error
// chain; logging at this layer would lose both. Pattern: the caller logs,
// then calls Write.
//
// On the **encoder-error path** (json.Encode failed after WriteHeader, which
// in practice means the client hung up), Write falls back to
// slog.Default() because no caller-supplied logger is in scope at that
// point. The headers are already on the wire and there is no useful
// recovery; the log line is the only remaining signal.
func Write(w http.ResponseWriter, status int, code Code, details any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	// The encoder writes to a buffered network connection; an error here
	// means the client hung up. There is nothing left to do for the wire
	// (the headers are already sent) — surface the failure as a log event
	// at the caller's level if a logger is supplied.
	if err := json.NewEncoder(w).Encode(envelope{Error: code, Details: details}); err != nil {
		slog.Default().Error("apierror.Write: encoding response envelope",
			slog.String("code", string(code)),
			slog.Any("err", err))
	}
}

// Internal is shorthand for Write(w, 500, CodeInternalError, nil). Use it
// from middleware (panic recovery, unexpected store errors) where the
// status and code are fixed and the details would leak internal state.
// dc-02 forbids returning internal error text to the wire; this helper is
// the canonical "log internally, return opaque externally" pivot.
func Internal(w http.ResponseWriter) {
	Write(w, http.StatusInternalServerError, CodeInternalError, nil)
}
