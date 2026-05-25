// Package store is the Postgres data-access layer. It owns the pgxpool
// connection to Supabase Postgres and the WithClaims helper that makes
// every transactional handler RLS-aware (per ADR-0011 — JWT-aware
// connection; RLS is load-bearing).
//
// The package connects as the `authenticated` Postgres role (never
// service-role per ADR-0011) and, at the start of every transactional
// call, executes `SET LOCAL request.jwt.claim.sub = '<user_id>'` so the
// data track's `(select auth.uid())`-anchored policies enforce per-row
// filtering inside the database. A bug in a Go handler cannot leak a row
// belonging to another user because Postgres refuses the query.
//
// Depends on: github.com/jackc/pgx/v5 + /v5/pgxpool (the pool and Tx
// abstractions; chosen per plan §4.2 — direct SQL, no ORM),
// github.com/google/uuid (the user-id type the handler hands us from the
// JWT middleware's context), internal/config (the SupabaseDBURL).
// Depended on by: internal/api handlers (each calls Pool.WithClaims at
// the entry point of any DB-touching path); cmd/sous-chef-api (constructs
// the Pool at boot and passes it to the server).
// Why it exists: ADR-0011 places the JWT-aware `SET LOCAL` at every
// transaction boundary; centralising the pattern here means a handler
// author cannot forget it. The boundary is exactly one function call —
// pool.WithClaims(ctx, userID, func(tx pgx.Tx) error { ... }) — and a
// reviewer can confirm RLS coverage by grepping for the call site.
package store

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// jwtClaimSubGUC is the Postgres GUC the data track's RLS policies read
// via `auth.uid()`. Supabase configures the GUC name as
// `request.jwt.claim.sub`; setting it `LOCAL` (transaction scope) is what
// makes the pool safe — the value disappears at COMMIT or ROLLBACK and
// the connection returns to the pool clean.
const jwtClaimSubGUC = "request.jwt.claim.sub"

// Pool wraps a pgx connection pool with the RLS-aware WithClaims helper.
// Construct one Pool per process at boot via Open and share it across
// handlers — pgxpool.Pool is safe for concurrent use.
type Pool struct {
	pool *pgxpool.Pool
}

// Open parses dsn and constructs a pool. The pool size and other
// connection-config knobs use pgx's defaults; tuning lands in a future
// task when CloudWatch metrics surface real saturation (plan §8 R3). The
// initial Ping confirms the credentials and network reachability so a
// misconfigured deploy fails at boot, not on the first authenticated
// request.
func Open(ctx context.Context, dsn string) (*Pool, error) {
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, fmt.Errorf("store: parsing dsn: %w", err)
	}
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("store: opening pool: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("store: pinging pool: %w", err)
	}
	return &Pool{pool: pool}, nil
}

// FromPool wraps an existing *pgxpool.Pool. Used in tests that construct
// a pool against a local Supabase stack (or any other Postgres) with
// custom configuration; production code calls Open.
func FromPool(pool *pgxpool.Pool) *Pool {
	return &Pool{pool: pool}
}

// Close releases the underlying pool. Call at process shutdown after all
// inflight requests have drained.
func (p *Pool) Close() {
	if p.pool != nil {
		p.pool.Close()
	}
}

// Ping forwards to the underlying pool's Ping. Used by /healthz to
// surface a DB-unhealthy process as 503 (plan §5 Phase C1).
func (p *Pool) Ping(ctx context.Context) error {
	if p.pool == nil {
		return errors.New("store: pool is not initialised")
	}
	if err := p.pool.Ping(ctx); err != nil {
		return fmt.Errorf("store: ping: %w", err)
	}
	return nil
}

// Querier is the read-only interface every store-method that takes a
// transaction satisfies. Defined in the consumer package per dc-02
// (interfaces live where they're used); callers pass pgx.Tx by concrete
// type from inside the WithClaims callback, so this type is only useful
// for handlers that want to compose read methods across packages.
type Querier interface {
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
}

// WithClaims opens a transaction, sets the JWT claims on the session so
// RLS fires, runs fn, and commits — or rolls back on any error fn
// returns. The `LOCAL` scope on the GUC ensures the connection returns
// to the pool clean (no claim leaks across requests).
//
// The userID is taken from the context the JWT middleware attached
// (internal/auth.UserIDFromContext). A uuid.Nil is rejected — the caller
// should always have a verified id by the time WithClaims runs; passing
// Nil means the auth middleware did not run or the handler skipped the
// check, and the call must fail closed rather than execute a
// well-formed-but-empty `auth.uid()`.
//
// On a fn error, the rollback is best-effort — if the rollback itself
// fails, the original fn error is preserved and the rollback failure is
// attached via errors.Join so neither is lost. The named return value
// `err` is what the defer reads and (on rollback failure) writes back.
func (p *Pool) WithClaims(ctx context.Context, userID uuid.UUID, fn func(tx pgx.Tx) error) (err error) {
	if p.pool == nil {
		return errors.New("store.WithClaims: pool is not initialised")
	}
	if userID == uuid.Nil {
		return errors.New("store.WithClaims: userID is uuid.Nil (auth middleware did not attach an identity)")
	}
	if fn == nil {
		return errors.New("store.WithClaims: fn is required")
	}

	tx, beginErr := p.pool.BeginTx(ctx, pgx.TxOptions{})
	if beginErr != nil {
		return fmt.Errorf("store.WithClaims: begin: %w", beginErr)
	}

	// Best-effort rollback on any return path that doesn't commit. The
	// deferred call runs after the explicit Commit attempt below; pgx's
	// Rollback is a no-op on an already-committed transaction and
	// returns pgx.ErrTxClosed, which we deliberately ignore so the happy
	// path stays quiet. On a real rollback failure, errors.Join attaches
	// it to the outgoing error so a caller logging `%v` sees both — the
	// docstring's contract.
	committed := false
	defer func() {
		if committed {
			return
		}
		if rbErr := tx.Rollback(ctx); rbErr != nil && !errors.Is(rbErr, pgx.ErrTxClosed) {
			err = errors.Join(err, fmt.Errorf("store.WithClaims: rollback: %w", rbErr))
		}
	}()

	// `SET LOCAL <guc> = <value>` is the documented Supabase idiom but
	// Postgres SET does not accept $1 binding, which would force us to
	// format the user-id into the SQL string. The set_config(name, value,
	// is_local=true) function is the parameterised equivalent — same
	// transaction-scoped semantics, but it accepts pgx's normal
	// parameter binding so no SQL fragment is ever assembled from
	// untrusted text. userID has already been parsed to uuid.UUID by
	// the auth middleware, so there is no injection surface at all; the
	// binding is belt-and-suspenders.
	if _, err := tx.Exec(ctx, "SELECT set_config($1, $2, true)", jwtClaimSubGUC, userID.String()); err != nil {
		return fmt.Errorf("store.WithClaims: set jwt claim: %w", err)
	}

	if err := fn(tx); err != nil {
		return fmt.Errorf("store.WithClaims: fn: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("store.WithClaims: commit: %w", err)
	}
	committed = true
	return nil
}
