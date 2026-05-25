-- seed.sql — minimal dev-only seed data.
--
-- Depends on:     supabase/schemas/* applied to a clean local stack.
-- Depended on by: nothing in production. This file is loaded by
--                 `supabase db reset` against the LOCAL stack only;
--                 staging and prod `supabase db push` operations do NOT
--                 run seed.sql (it is not packaged into migrations).
-- Why it exists:  the backend and iOS Builders both need at least one
--                 user row to write against when they bring up their
--                 stacks. We seed a single deterministic test user so
--                 their integration tests have something to point at.
--
-- Test user identity:
--   email: dev-seed@example.invalid
--   id:    fixed UUID so other tracks can refer to it by name.
--
-- Why we don't seed CFO / meal-plan / cookbook rows yet:
--   * Without a real Supabase Auth session for this user, RLS-protected
--     inserts via the authenticated role would fail. The auth.users
--     insert below uses the `service_role` implicit during seed-load
--     (supabase db reset connects as the postgres superuser), which can
--     insert into auth.users directly; but writing into public.* with
--     RLS on requires either a `SET LOCAL request.jwt.claim.sub` or
--     issuing the insert as the postgres superuser (FORCE RLS still
--     blocks the superuser by design).
--   * Track-data plan task 19 generates richer seed data via a Go
--     script that uses the Supabase Admin API to mint a JWT. That
--     script is **out of scope** for the foundation phase — we land
--     the user row here so any tests that just need a valid user_id
--     have one, and defer realistic CFO/plan/cookbook seeding to the
--     follow-up phase.

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
