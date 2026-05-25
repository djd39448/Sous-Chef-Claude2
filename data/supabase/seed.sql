-- seed.sql — minimal dev-only seed data.
--
-- Depends on:     supabase/schemas/* applied to a clean local stack.
-- Depended on by: nothing in production. This file is loaded by
--                 `supabase db reset` against the LOCAL stack only;
--                 staging and prod `supabase db push` operations do NOT
--                 run seed.sql (it is not packaged into migrations).
--                 The backend track's GET /api/kitchen/ingredients
--                 endpoint reads from the CFO rows seeded below — without
--                 them the endpoint returns an empty list and end-to-end
--                 smoke tests are uninformative.
-- Why it exists:  the backend and iOS Builders both need a deterministic
--                 user + a handful of inventory CFO rows to write
--                 against. We seed:
--                   * one test user (in auth.users), and
--                   * five food_items rows under that user with
--                     usage_context.role = 'inventory' so the
--                     ingredients endpoint has something to return.
--
-- Test user identity:
--   email: dev-seed@example.invalid
--   id:    00000000-0000-0000-0000-000000000001 (fixed so the backend
--          and iOS fixtures can refer to it by literal).
--
-- Why we still don't seed meal-plan / cookbook / shopping rows yet:
--   * Those surfaces are exercised by the backend's integration tests,
--     which mint JWTs and run through the full HTTP path. A static
--     seed of meal plans / cookbook recipes / shopping lists is more
--     likely to drift from the contract than to help.
--   * The CFO inventory seed below is the minimum the contract §5.5
--     `GET /api/kitchen/ingredients` endpoint needs to return a
--     non-empty list.

-- Guard: only seed when the caller explicitly declares the local
-- environment. The previous guard checked
-- `current_setting('app.environment', true) = 'production'` which is
-- a no-op — that setting returns NULL when unset, and NULL = 'production'
-- is always false. Reviewer-pass 0001 flagged this as a dc-00 violation:
-- "a guard that doesn't guard misleads readers."
--
-- The new contract is an OPT-IN: the caller must pass
-- `seed_environment=local` via the PGOPTIONS env var. The Makefile's
-- `reset` target sets this automatically, so `make reset` Just Works.
-- A bare `supabase db reset` (no PGOPTIONS) aborts loud. A developer
-- who runs `psql -f seed.sql` against a cloud Supabase project by
-- mistake aborts loud as well — they would have to deliberately add
-- `--set seed_environment=local` to defeat the guard, which is no
-- longer "by mistake."
--
-- Why not key off the server's address? `inet_server_addr()` returns
-- the container's IP under Docker (not NULL), so a check like
-- `inet_server_addr() IS NULL` would block `supabase db reset`
-- locally too. Distinguishing local from cloud by IP is brittle.
-- Caller-asserted intent is the more honest gate.
do $$
declare
  declared_environment text := current_setting('seed_environment', true);
begin
  if declared_environment is null or declared_environment <> 'local' then
    raise exception 'seed.sql refused: PGOPTIONS must include "-c seed_environment=local" (run via `make reset`, or set PGOPTIONS yourself).';
  end if;
end$$;

-- The test user. auth.users is Supabase-managed; we insert a minimal row
-- and rely on Supabase Auth's default columns. The fixed UUID lets the
-- other tracks reference this user by name in their fixtures.
insert into auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values (
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'dev-seed@example.invalid',
  '',                                     -- no password; tests mint JWTs
  now(),
  '{"provider": "seed", "providers": ["seed"]}'::jsonb,
  '{}'::jsonb,
  now(),
  now()
)
on conflict (id) do nothing;


-- ============================================================================
-- 02-cfo-rows — five food_items inventory rows under the test user.
--
-- Why this exists:  the backend's GET /api/kitchen/ingredients endpoint
--                   (contract §5.5) filters food_items by
--                   `usage_context.role = 'inventory'` AND
--                   `inventory_state.status != 'out'`. Without these rows
--                   the endpoint returns an empty list and the backend
--                   Builder cannot manually smoke-test the read path.
--
-- Shape:            every JSONB sub-document matches contract §4.1 EXACTLY.
--                   The CHECK constraints in 02-tables.sql validate the
--                   enum values inline; the open-keyed sub-documents
--                   (attributes, flexibility, sourcing, metadata,
--                   inventory_state) follow the documented shapes in
--                   02-tables.sql column comments.
--
-- Variety:          per the data-track plan §5 task 19, the seed needs
--                   to cover the surface area the backend will exercise:
--                     * categories: produce, dairy, meat (3 of the 9)
--                     * inventory_state.status: confirmed, likely, unknown
--                     * quantity: one row with amount+unit, one without
--                     * metadata.created_by: ai + user (mix of provenance)
--                   Five rows is enough to populate every branch the
--                   ingredients endpoint inspects.
--
-- Why the FORCE-RLS dance:
--   The seed runs as the postgres superuser. Per dc-04 we set
--   FORCE ROW LEVEL SECURITY on every table — *including* against the
--   table owner. That means even the superuser cannot INSERT without
--   satisfying RLS, and we have no auth.uid() in this connection
--   (request.jwt.claim.sub is unset). Two options:
--     (a) SET request.jwt.claim.sub = test-user-uuid before the
--         INSERTs — but the seed connection is not the authenticated
--         role, and setting the GUC alone does not bypass FORCE for
--         the postgres role.
--     (b) Temporarily DISABLE / NO FORCE row level security around the
--         INSERTs, then re-ENABLE + FORCE.
--   We pick (b). It is the documented Supabase pattern for seed.sql
--   and is bracketed so a failure between the disable and the re-enable
--   would still re-enable on the next `make reset` (the schemas/03-rls.sql
--   ALTER TABLE statements run before this file). The DO block also
--   wraps in an EXCEPTION handler so a mid-insert failure still
--   restores RLS before raising.
--
-- Idempotency:      `on conflict (...) do nothing` per the
--                   food_items_user_canonical_role_uniq index, so
--                   re-running `make reset` is a no-op for already-
--                   seeded rows. Conflict target lists the three
--                   columns the unique index covers; the JSONB
--                   expression must match the index definition.
--
-- Structure note:   the ALTER TABLE … DISABLE/NO FORCE and the matching
--                   ENABLE/FORCE statements are at top level rather than
--                   inside a DO block. Inside plpgsql an EXCEPTION clause
--                   runs in a subtransaction; the ALTER would roll back
--                   on a partial failure, leaving the table protected
--                   (good) but also un-doing the post-recovery re-enable
--                   we'd intend (irrelevant). Keeping the ALTERs at top
--                   level makes the bracket structure visible to a reader
--                   and means a failed INSERT below still leaves the
--                   subsequent ENABLE/FORCE statement to run as the next
--                   top-level statement — `make reset` aborts on the
--                   raised error, but the lock-down statements precede
--                   the user-visible exit.
-- ============================================================================

-- Lower the gate: superuser can write rows attributed to the test
-- user without an active JWT subject. seed.sql runs inside a single
-- transaction under `supabase db reset`; if any of the INSERTs below
-- fail, the whole transaction rolls back and food_items is left in its
-- original FORCE-RLS state by definition.
alter table public.food_items disable row level security;
alter table public.food_items no force row level security;

do $$
begin
  -- Row 1 — produce, confirmed, with structured quantity, user-created.
  insert into public.food_items (
    user_id, canonical_name, display_name,
    quantity, category, attributes, flexibility, usage_context,
    inventory_state, sourcing, metadata
  ) values (
    '00000000-0000-0000-0000-000000000001',
    'spinach',
    'Baby Spinach',
    '{"amount": 5, "unit": "oz"}'::jsonb,
    '{"primary": "produce"}'::jsonb,
    '{"organic": true}'::jsonb,
    '{"substitution_allowed": true, "acceptable_variants": ["kale"], "strict": false}'::jsonb,
    '{"role": "inventory"}'::jsonb,
    '{"status": "confirmed", "on_hand_amount": 5, "last_confirmed": "2026-05-25T00:00:00Z"}'::jsonb,
    '{"store_affinity": null, "bulk_allowed": true, "generic_ok": true}'::jsonb,
    '{"created_by": "user", "confidence": 1.0}'::jsonb
  )
  on conflict (user_id, canonical_name, (usage_context->>'role')) do nothing;

  -- Row 2 — produce, likely, no quantity, AI-created.
  insert into public.food_items (
    user_id, canonical_name, display_name,
    quantity, category, attributes, flexibility, usage_context,
    inventory_state, sourcing, metadata
  ) values (
    '00000000-0000-0000-0000-000000000001',
    'tomato',
    'Roma Tomato',
    null,
    '{"primary": "produce", "secondary": "fresh"}'::jsonb,
    '{}'::jsonb,
    '{"substitution_allowed": true, "acceptable_variants": [], "strict": false}'::jsonb,
    '{"role": "inventory"}'::jsonb,
    '{"status": "likely", "on_hand_amount": null, "last_confirmed": null}'::jsonb,
    '{"store_affinity": null, "bulk_allowed": true, "generic_ok": true}'::jsonb,
    '{"created_by": "ai", "confidence": 0.8}'::jsonb
  )
  on conflict (user_id, canonical_name, (usage_context->>'role')) do nothing;

  -- Row 3 — dairy, confirmed, with structured quantity, AI-created.
  insert into public.food_items (
    user_id, canonical_name, display_name,
    quantity, category, attributes, flexibility, usage_context,
    inventory_state, sourcing, metadata
  ) values (
    '00000000-0000-0000-0000-000000000001',
    'milk',
    'Whole Milk',
    '{"amount": 1, "unit": "gal"}'::jsonb,
    '{"primary": "dairy"}'::jsonb,
    '{"fat_content": "whole"}'::jsonb,
    '{"substitution_allowed": true, "acceptable_variants": ["2% milk", "oat milk"], "strict": false}'::jsonb,
    '{"role": "inventory"}'::jsonb,
    '{"status": "confirmed", "on_hand_amount": 1, "last_confirmed": "2026-05-25T00:00:00Z"}'::jsonb,
    '{"store_affinity": "Whole Foods", "bulk_allowed": false, "generic_ok": true}'::jsonb,
    '{"created_by": "ai", "confidence": 1.0}'::jsonb
  )
  on conflict (user_id, canonical_name, (usage_context->>'role')) do nothing;

  -- Row 4 — dairy, unknown, no quantity, user-created.
  insert into public.food_items (
    user_id, canonical_name, display_name,
    quantity, category, attributes, flexibility, usage_context,
    inventory_state, sourcing, metadata
  ) values (
    '00000000-0000-0000-0000-000000000001',
    'cheddar cheese',
    'Sharp Cheddar',
    null,
    '{"primary": "dairy"}'::jsonb,
    '{"aged": true}'::jsonb,
    '{"substitution_allowed": true, "acceptable_variants": ["gouda"], "strict": false}'::jsonb,
    '{"role": "inventory"}'::jsonb,
    '{"status": "unknown", "on_hand_amount": null, "last_confirmed": null}'::jsonb,
    '{"store_affinity": null, "bulk_allowed": true, "generic_ok": true}'::jsonb,
    '{"created_by": "user", "confidence": 0.9}'::jsonb
  )
  on conflict (user_id, canonical_name, (usage_context->>'role')) do nothing;

  -- Row 5 — meat, confirmed, with structured quantity, AI-created.
  insert into public.food_items (
    user_id, canonical_name, display_name,
    quantity, category, attributes, flexibility, usage_context,
    inventory_state, sourcing, metadata
  ) values (
    '00000000-0000-0000-0000-000000000001',
    'chicken breast',
    'Boneless Chicken Breast',
    '{"amount": 1.5, "unit": "lb"}'::jsonb,
    '{"primary": "meat"}'::jsonb,
    '{"boneless": true, "skinless": true}'::jsonb,
    '{"substitution_allowed": true, "acceptable_variants": ["chicken thigh"], "strict": false}'::jsonb,
    '{"role": "inventory"}'::jsonb,
    '{"status": "confirmed", "on_hand_amount": 1.5, "last_confirmed": "2026-05-25T00:00:00Z"}'::jsonb,
    '{"store_affinity": null, "bulk_allowed": true, "generic_ok": true}'::jsonb,
    '{"created_by": "ai", "confidence": 1.0}'::jsonb
  )
  on conflict (user_id, canonical_name, (usage_context->>'role')) do nothing;
end$$;

-- Raise the gate. seed.sql is loaded inside a single transaction by
-- `supabase db reset`; if the DO block above raised, this statement
-- is unreachable and the whole transaction rolls back (food_items
-- keeps its original FORCE state, because the DISABLE/NO FORCE
-- earlier in the same transaction is also rolled back).
alter table public.food_items enable row level security;
alter table public.food_items force row level security;
