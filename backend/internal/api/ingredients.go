// Package api holds the HTTP handlers for contract §5 endpoints. Each
// file groups the handlers of one resource family (ingredients here;
// conversations, meal plans, cookbook, shopping in later phases). A
// handler is small and predictable per dc-02: decode → call store →
// encode. No business logic; no SQL.
//
// Depends on: internal/auth (UserIDFromContext for the verified user id),
// internal/store (Pool.WithClaims wraps each DB-touching call),
// internal/apierror (error envelope writer per contract §3.5),
// internal/domain (the wire types), log/slog (request-scoped logger).
// Depended on by: internal/server (MountAuth registers these handlers
// behind the JWT middleware), cmd/sous-chef-api indirectly.
// Why it exists: the handler layer is the contract's enforcement
// surface; isolating it from auth, storage, and serialisation lets each
// handler stay short enough to read in one screen.
package api

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"

	"github.com/jackc/pgx/v5"

	"github.com/djd39448/Sous-Chef-Claude2/backend/internal/apierror"
	"github.com/djd39448/Sous-Chef-Claude2/backend/internal/auth"
	"github.com/djd39448/Sous-Chef-Claude2/backend/internal/domain"
	"github.com/djd39448/Sous-Chef-Claude2/backend/internal/store"
)

// errMissingUserID is the sentinel the PoolLister returns when an
// upstream invariant breaks — the handler chain ran but no UUID landed
// in the context. The handler surfaces this as internal_error per
// contract §3.5; it should never reach a wire response in practice.
var errMissingUserID = errors.New("api: no user id in request context")

// IngredientLister is the consumer-side interface ingredients.Handler
// depends on. Per dc-02 the interface lives in the consumer package and
// is one method wide. Production code passes a *store.Pool wrapped in a
// tiny adapter (poolListerAdapter, below); tests pass a fake.
type IngredientLister interface {
	// ListInventory returns the caller's CFO inventory rows. The caller
	// (a handler) supplies the user id from the JWT context; the
	// implementation is responsible for entering the RLS-aware
	// transaction (production wraps store.Pool.WithClaims).
	ListInventory(r *http.Request) ([]domain.FoodItem, error)
}

// IngredientsHandler is the resource-family handler struct. It carries
// its dependencies as fields rather than reaching for package globals
// (dc-02). Construct via NewIngredientsHandler.
type IngredientsHandler struct {
	lister IngredientLister
	logger *slog.Logger
}

// NewIngredientsHandler constructs an IngredientsHandler. Nil arguments
// are rejected at construction because every handler call would panic
// on first use otherwise.
func NewIngredientsHandler(lister IngredientLister, logger *slog.Logger) *IngredientsHandler {
	if lister == nil {
		panic("api.NewIngredientsHandler: lister is required")
	}
	if logger == nil {
		panic("api.NewIngredientsHandler: logger is required")
	}
	return &IngredientsHandler{lister: lister, logger: logger}
}

// ingredientsResponse is the contract §5.5 wire shape:
// `{ "ingredients": [<food_item>] }`. The slice is non-nil even when
// empty so the JSON encodes as `[]` not `null` — iOS clients that
// iterate the array unconditionally are happier with `[]`.
type ingredientsResponse struct {
	Ingredients []domain.FoodItem `json:"ingredients"`
}

// List implements GET /api/kitchen/ingredients per contract §5.5.
// The auth middleware has already verified the JWT and attached the
// user id to r.Context() — if it has not, the handler fails closed
// with `internal_error` (this is the same fail-closed signal the store
// helper raises on uuid.Nil; surfacing it here means the handler
// returns 500 with no detail rather than a 200 with somebody else's
// rows or 200 with [] under RLS).
func (h *IngredientsHandler) List(w http.ResponseWriter, r *http.Request) {
	if _, ok := auth.UserIDFromContext(r.Context()); !ok {
		h.logger.LogAttrs(
			r.Context(), slog.LevelError,
			"ingredients.List called without auth middleware",
		)
		apierror.Internal(w)
		return
	}

	items, err := h.lister.ListInventory(r)
	if err != nil {
		h.logger.LogAttrs(
			r.Context(), slog.LevelError,
			"ingredients.List store error",
			slog.Any("err", err),
		)
		apierror.Internal(w)
		return
	}
	// Force the slice non-nil so encoding yields `[]` rather than `null`.
	// iOS clients iterate the array unconditionally and a `null` value
	// would crash the SwiftUI binding.
	if items == nil {
		items = []domain.FoodItem{}
	}

	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	if err := json.NewEncoder(w).Encode(ingredientsResponse{Ingredients: items}); err != nil {
		// Headers already on the wire — log and move on (same pattern
		// as internal/apierror.Write).
		h.logger.LogAttrs(
			r.Context(), slog.LevelError,
			"ingredients.List encode",
			slog.Any("err", err),
		)
	}
}

// PoolLister adapts a *store.Pool to the IngredientLister interface so
// the handler does not reach for store.Pool directly. The adapter is
// the only place WithClaims is composed with ListInventory for this
// endpoint; tests sidestep it via a hand-written fake.
//
// Defined in api (not in store) because dc-02 puts consumer interfaces
// in the consumer package — and the adapter is the bridge between that
// interface and the store's concrete API.
type PoolLister struct {
	pool   *store.Pool
	logger *slog.Logger
}

// NewPoolLister builds the production adapter. The pool MUST already be
// open (callers run store.Open at boot).
func NewPoolLister(pool *store.Pool, logger *slog.Logger) *PoolLister {
	if pool == nil {
		panic("api.NewPoolLister: pool is required")
	}
	if logger == nil {
		panic("api.NewPoolLister: logger is required")
	}
	return &PoolLister{pool: pool, logger: logger}
}

// ListInventory enters an RLS-aware transaction via Pool.WithClaims and
// delegates to store.ListInventory. The user id comes from the JWT
// context attached by the auth middleware; the absence of one here
// would be a bug in the handler chain — fail closed.
func (a *PoolLister) ListInventory(r *http.Request) ([]domain.FoodItem, error) {
	userID, ok := auth.UserIDFromContext(r.Context())
	if !ok {
		return nil, errMissingUserID
	}
	var out []domain.FoodItem
	if err := a.pool.WithClaims(r.Context(), userID, func(tx pgx.Tx) error {
		items, err := store.ListInventory(r.Context(), tx)
		if err != nil {
			return err
		}
		out = items
		return nil
	}); err != nil {
		return nil, err
	}
	return out, nil
}
