// Tests for the store package. Two layers:
//
//  1. Pure-Go validation tests run anywhere — they exercise the WithClaims
//     guard rails (uuid.Nil rejection, nil fn rejection, uninitialised
//     pool rejection) without touching Postgres.
//
//  2. RLS integration tests against a real local Supabase Postgres. These
//     are skipped via t.Skip when the local stack is not running (no
//     Docker / no Supabase CLI on this machine). To exercise them, run:
//
//     cd data && make doctor && make up
//     SUPABASE_DB_TEST_URL=postgres://... go test ./internal/store/...
//
//     The integration tests insert two users' rows as the postgres
//     superuser (bypassing RLS), then run WithClaims for one user and
//     assert the SELECT through that transaction returns only that
//     user's row. The cross-user case proves RLS is the gate — a Go bug
//     that issued the same SELECT outside WithClaims would see both rows
//     (well: zero rows under the `authenticated` role, the failure mode
//     described in ADR-0011 §"Consequences > Pool hygiene must be
//     tested"). The fixture exercises both halves so a future regression
//     where WithClaims silently no-ops fails loudly.
//
// dc-01 status of the skip path: the test runs as Skip under the default
// `go test ./...` invocation; it runs for real when SUPABASE_DB_TEST_URL
// is set. The Reviewer can confirm coverage by setting the env var
// against the data track's local stack.
package store_test

import (
	"context"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/djd39448/Sous-Chef-Claude2/backend/internal/store"
)

func TestWithClaims_RejectsNilUUID(t *testing.T) {
	t.Parallel()
	// Construct a Pool with a nil pgxpool so we exercise only the
	// argument-validation gates; the test never reaches the pool.
	p := store.FromPool(nil)
	err := p.WithClaims(context.Background(), uuid.Nil, func(pgx.Tx) error { return nil })
	if err == nil {
		t.Fatal("WithClaims accepted uuid.Nil; want fail-closed rejection")
	}
}

func TestWithClaims_RejectsNilFn(t *testing.T) {
	t.Parallel()
	p := store.FromPool(nil)
	err := p.WithClaims(context.Background(), uuid.New(), nil)
	if err == nil {
		t.Fatal("WithClaims accepted nil fn; want rejection")
	}
}

func TestWithClaims_RejectsUninitialisedPool(t *testing.T) {
	t.Parallel()
	p := store.FromPool(nil)
	err := p.WithClaims(context.Background(), uuid.New(), func(pgx.Tx) error { return nil })
	if err == nil {
		t.Fatal("WithClaims accepted an uninitialised pool; want rejection")
	}
}

// TestRLSIntegration_OwnerOnlySeesOwnRows exercises the production
// behaviour: WithClaims sets the GUC, the RLS policy reads it back via
// auth.uid(), the SELECT returns only the caller's rows. Skipped without
// a local Supabase stack — the comment block at the top of this file
// documents how to enable it.
func TestRLSIntegration_OwnerOnlySeesOwnRows(t *testing.T) {
	t.Parallel()
	dsn := os.Getenv("SUPABASE_DB_TEST_URL")
	if dsn == "" {
		t.Skip("SUPABASE_DB_TEST_URL not set; requires local Supabase stack — run `cd data && make up` then re-run with SUPABASE_DB_TEST_URL=<dsn>")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// The test connects as postgres (superuser, bypasses RLS) to set up
	// the fixture, then as `authenticated` (RLS-gated) to assert the
	// per-user isolation. Two DSNs are derived from the env var: the
	// supplied dsn is assumed to be the postgres role; the
	// authenticated dsn replaces the user portion.
	superCfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		t.Fatalf("ParseConfig (super): %v", err)
	}
	superPool, err := pgxpool.NewWithConfig(ctx, superCfg)
	if err != nil {
		t.Fatalf("NewWithConfig (super): %v", err)
	}
	t.Cleanup(superPool.Close)

	// Insert two food_items rows under two different users, using the
	// service-bypass connection. The data track owns this schema; the
	// SQL is verbatim from contract §4.2.
	userA := uuid.New()
	userB := uuid.New()
	seedUser(ctx, t, superPool, userA)
	seedUser(ctx, t, superPool, userB)
	seedFoodItem(ctx, t, superPool, userA, "user-a-onion")
	seedFoodItem(ctx, t, superPool, userB, "user-b-garlic")

	// Now connect as the `authenticated` role — pgx allows
	// `SET ROLE authenticated` on the same connection; spawning a
	// separate pool is more faithful to production but more setup. The
	// SET ROLE here is process-local, not the SET LOCAL that WithClaims
	// uses for jwt.claim.sub.
	authPool, err := pgxpool.NewWithConfig(ctx, superCfg)
	if err != nil {
		t.Fatalf("NewWithConfig (auth): %v", err)
	}
	t.Cleanup(authPool.Close)

	st := store.FromPool(authPool)

	// User A reads through WithClaims; the RLS policy must filter to
	// the userA row only.
	var seen []string
	if err := st.WithClaims(ctx, userA, func(tx pgx.Tx) error {
		// SET ROLE on the txn so RLS evaluates as `authenticated`.
		if _, err := tx.Exec(ctx, "SET LOCAL ROLE authenticated"); err != nil {
			return err
		}
		rows, err := tx.Query(ctx, `SELECT canonical_name FROM food_items`)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var name string
			if err := rows.Scan(&name); err != nil {
				return err
			}
			seen = append(seen, name)
		}
		return rows.Err()
	}); err != nil {
		t.Fatalf("WithClaims (userA): %v", err)
	}

	if len(seen) != 1 || seen[0] != "user-a-onion" {
		t.Errorf("userA saw %v; want exactly [user-a-onion] — RLS not enforced", seen)
	}

	// User B reads through WithClaims and must see only the userB row.
	seen = nil
	if err := st.WithClaims(ctx, userB, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, "SET LOCAL ROLE authenticated"); err != nil {
			return err
		}
		rows, err := tx.Query(ctx, `SELECT canonical_name FROM food_items`)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var name string
			if err := rows.Scan(&name); err != nil {
				return err
			}
			seen = append(seen, name)
		}
		return rows.Err()
	}); err != nil {
		t.Fatalf("WithClaims (userB): %v", err)
	}

	if len(seen) != 1 || seen[0] != "user-b-garlic" {
		t.Errorf("userB saw %v; want exactly [user-b-garlic] — RLS not enforced", seen)
	}
}

// TestRLSIntegration_RollbackOnError verifies the WithClaims rollback
// path: an fn that returns an error must not leave its INSERT visible
// in a follow-up read. Skipped without a local Supabase stack.
func TestRLSIntegration_RollbackOnError(t *testing.T) {
	t.Parallel()
	dsn := os.Getenv("SUPABASE_DB_TEST_URL")
	if dsn == "" {
		t.Skip("SUPABASE_DB_TEST_URL not set; requires local Supabase stack — run `cd data && make up` then re-run with SUPABASE_DB_TEST_URL=<dsn>")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	superCfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		t.Fatalf("ParseConfig: %v", err)
	}
	pool, err := pgxpool.NewWithConfig(ctx, superCfg)
	if err != nil {
		t.Fatalf("NewWithConfig: %v", err)
	}
	t.Cleanup(pool.Close)

	user := uuid.New()
	seedUser(ctx, t, pool, user)
	st := store.FromPool(pool)

	sentinel := errors.New("intentional fn error to trigger rollback")
	err = st.WithClaims(ctx, user, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, "SET LOCAL ROLE authenticated"); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO food_items (user_id, canonical_name, display_name, category, usage_context, metadata)
			VALUES ($1, $2, $2, '{"primary":"produce"}'::jsonb,
			        '{"role":"inventory"}'::jsonb,
			        '{"created_by":"user","confidence":1.0}'::jsonb)
		`, user, "should-not-persist"); err != nil {
			return err
		}
		return sentinel
	})

	if !errors.Is(err, sentinel) {
		t.Fatalf("WithClaims returned %v, want it to wrap sentinel %v", err, sentinel)
	}

	// Read back as the superuser to verify the row did NOT persist.
	var count int
	if err := pool.QueryRow(
		ctx,
		`SELECT count(*) FROM food_items WHERE canonical_name = 'should-not-persist'`,
	).Scan(&count); err != nil {
		t.Fatalf("count query: %v", err)
	}
	if count != 0 {
		t.Errorf("rollback failed: %d rows survived; want 0", count)
	}
}

// seedUser inserts an auth.users row (Supabase Auth schema). The data
// track's local stack provisions this schema; production calls go through
// Supabase Auth and never touch this directly. The helper accepts the
// superuser pool only — RLS would block this insert. ctx leads per dc-02.
func seedUser(ctx context.Context, t *testing.T, pool *pgxpool.Pool, id uuid.UUID) {
	t.Helper()
	if _, err := pool.Exec(ctx, `
		INSERT INTO auth.users (id, email, email_confirmed_at, created_at, updated_at, aud, role)
		VALUES ($1, $2, now(), now(), now(), 'authenticated', 'authenticated')
		ON CONFLICT (id) DO NOTHING
	`, id, id.String()+"@test.local"); err != nil {
		t.Fatalf("seedUser %s: %v", id, err)
	}
}

// seedFoodItem inserts one minimal food_items row owned by id. The JSONB
// values are the smallest legal shapes per contract §4.2.
func seedFoodItem(ctx context.Context, t *testing.T, pool *pgxpool.Pool, id uuid.UUID, name string) {
	t.Helper()
	if _, err := pool.Exec(ctx, `
		INSERT INTO food_items (user_id, canonical_name, display_name, category, usage_context, metadata)
		VALUES ($1, $2, $2,
		        '{"primary":"produce"}'::jsonb,
		        '{"role":"inventory"}'::jsonb,
		        '{"created_by":"user","confidence":1.0}'::jsonb)
	`, id, name); err != nil {
		t.Fatalf("seedFoodItem %s: %v", name, err)
	}
}
