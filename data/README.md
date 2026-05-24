# `data/` — Supabase schema, RLS, and storage

Implements the data side of the shared contract: the eight tables, the
Row-Level Security policies that enforce per-user isolation, the storage
bucket for cookbook images, and the delete trigger that cascades into
storage.

## Stack

- **Database:** Supabase PostgreSQL (managed; project provisioned via
  Supabase Dashboard).
- **Auth:** Supabase Auth with **Sign in with Apple** + **email/OTP**
  providers (ADR-0003). No passwords.
- **Storage:** one bucket — `cookbook-images` — per-user RLS-scoped
  (ADR-0004).
- **Migrations:** Supabase CLI declarative-state workflow. Desired state
  lives in `supabase/schemas/*.sql`; migrations are diff-generated into
  `supabase/migrations/`; applied migrations are **never edited** (CI
  enforces via checksums).

## Track plan (authoritative)

[`plan/track-data.md`](https://github.com/djd39448/DevCore/blob/main/.devcore/memory/plan/track-data.md)
— foundation (project + Auth) → six tables → JSONB constraints → RLS per
table → storage bucket + delete trigger → seed data → migration ergonomics.

## Contract

[`contract/contract.md`](https://github.com/djd39448/DevCore/blob/main/.devcore/memory/contract/contract.md)
§4 (Supabase schema) is the implementation target. §3 (wire conventions —
JS-Sunday-first day-of-week, ISO dates) and §9 (open behavior rules)
also apply.

## Connection model

The Go backend connects as the `authenticated` Postgres role and sets
`request.jwt.claim.sub` per request. RLS policies use
`(select auth.uid())` to filter rows. See ADR-0011 — *JWT-aware Postgres
connection; RLS is the source of truth*.

## Layout

```
data/
  Makefile                          ← local stack management
  README.md                         ← this file
  supabase/
    config.toml                     ← Supabase CLI config (regenerate via
                                      `supabase init --force` once CLI
                                      is installed; see config.toml header)
    seed.sql                        ← dev-only test user (single row)
    schemas/                        ← desired state, hand-authored
      00-extensions.sql             ← pgcrypto + optional pg_uuidv7
      01-app-private.sql            ← app_private schema + RLS helpers
      02-tables.sql                 ← all 8 public tables + constraints
      03-rls.sql                    ← ENABLE/FORCE + per-op policies
      04-storage.sql                ← cookbook-images bucket + RLS
      05-triggers.sql               ← updated_at + cache-clear + image cascade
    migrations/                     ← diff-generated (empty until first
                                      `supabase db diff -f initial` runs)
  tests/                            ← pgTAP suite (run with `make test`)
    01_rls_cross_user_isolation.sql
```

## Local stack

Requires `supabase` CLI (`brew install supabase/tap/supabase`) and
Docker. Then:

```sh
cd data/
make up       # starts the local Supabase stack
make reset    # rebuilds the DB from schemas/ + seed.sql
make test     # runs pgTAP (requires pg_prove)
make down     # stops the stack
make doctor   # prints what's installed
```

`supabase db diff -f <name>` (`make diff name=<name>`) generates a
versioned migration capturing changes since the last applied migration.
Migrations are committed verbatim — **never edited** once applied.

## Foundation-phase status (as of 2026-05-24)

What's landed in this branch (`track-data-week1`):

- All eight tables (`food_items`, `meal_plans`, `meal_plan_days`,
  `cookbook_recipes`, `shopping_lists`, `shopping_list_items`,
  `kitchen_conversations`, `kitchen_messages`) with every CHECK
  constraint and named index from contract §4.
- `app_private` schema with `uuidv7()`, `set_updated_at()`, and three
  `SECURITY DEFINER` ownership helpers for the through-parent tables.
- RLS enabled and forced on every table; one policy per operation
  (`SELECT`/`INSERT`/`UPDATE`/`DELETE`) for owner tables; INSERT/SELECT
  only on `kitchen_messages` (append-only per contract §4.6).
- `cookbook-images` bucket (private, 8 MiB cap, `image/png` only) +
  per-user RLS policies on `storage.objects`.
- `BEFORE UPDATE updated_at` trigger on every table that has the column.
- Cache-clearing trigger on `meal_plan_days` (nulls cached recipe markdown
  + image prompt when `meal_name` changes).
- `AFTER DELETE` trigger on `cookbook_recipes` that removes the matching
  `storage.objects` row in the same transaction.
- pgTAP RLS test asserting user A cannot read / write user B's rows.

What was deferred (and why):

- **No first migration yet.** The track-data plan §5 task 15 cuts the
  initial migration with `supabase db diff -f initial`; that needs the
  CLI installed and the local stack running. This branch lands the
  declarative schemas only — a follow-up run generates the migration
  and commits it.
- **Cloud projects (dev/staging/prod) not provisioned.** Dave-action;
  the Supabase Dashboard work + 1Password key storage are §5 tasks
  1/16/17.
- **Sign in with Apple provider not configured.** Blocked on Dave's
  Apple Developer setup (Service ID, Team ID, Key ID, `.p8`). Documented
  in track-data §5 task 2/17.
- **Supabase CLI not installed.** `brew install supabase/tap/supabase`
  is the next operator step; until then `make doctor` prints the missing
  tooling.
- **Realistic seed data.** `seed.sql` lands one test user only. The
  richer dev seed (5 CFO rows, 1 meal plan, 1 cookbook recipe) is
  track-data §5 task 19 — needs a Go helper that mints JWTs via the
  Supabase Admin API.

## Standards

[`CODING_STANDARDS.md`](https://github.com/djd39448/DevCore/blob/main/CODING_STANDARDS.md)
`dc-04` (Supabase / PostgreSQL) governs every table, policy, and migration.
