-- 06_all_public_tables_force_rls.sql — every table in the public schema
-- has RLS ENABLED *and* FORCED.
--
-- Depends on:     pgTAP extension (`create extension pgtap`);
--                 supabase/schemas/* applied (via `supabase db reset`).
-- Depended on by: CI's `make test` target. Reviewer-pass 0001 §3 Data
--                 Should-fix #3 calls for this guard rail: a future
--                 table added without an ENABLE + FORCE statement in
--                 03-rls.sql is a public-data leak (track-data §8 R1).
-- Why it exists:  03-rls.sql lists each table by name. The list grows
--                 by hand. Without an automatic guard, a developer who
--                 adds a new public-schema table but forgets to add
--                 ENABLE + FORCE statements (or just forgets one of the
--                 two — the asymmetry is silent) ships a public table.
--                 This test reads pg_class for every table in the public
--                 schema and asserts both relrowsecurity (ENABLED) and
--                 relforcerowsecurity (FORCED) are true. The test fails
--                 loud the moment a forgotten table lands — no need to
--                 maintain a parallel list of "tables that must have
--                 RLS" inside the test.
--
-- Test strategy: one pgTAP assertion that pg_class shows
-- relrowsecurity = true AND relforcerowsecurity = true for EVERY table
-- in `public.*` (filtering pg_class.relkind = 'r' for tables only —
-- views, indexes, sequences are excluded). We expose the failing
-- tables in the assertion message so a regression is easy to diagnose.

begin;

-- One plan() — the test is a single boolean over all public tables.
select plan(1);

-- The assertion: an EXISTS subquery that finds any public table without
-- both flags set. If the subquery returns ZERO rows, every table is
-- properly secured. If it returns ANY rows, we fail and list them.
--
-- A small DO block builds a comma-separated list of unprotected tables
-- to surface in the failure message. The two-step (collect list, then
-- assert empty) keeps the failure mode self-explanatory: a reader sees
-- the table names directly, not a count.
do $$
declare
  unprotected_tables text;
begin
  select string_agg(c.relname, ', ' order by c.relname)
    into unprotected_tables
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relkind = 'r'  -- ordinary tables only (not views, not seqs)
     and (c.relrowsecurity = false or c.relforcerowsecurity = false);

  -- Stash the result in a session-local GUC so the pgTAP assertion
  -- can read it back. Using a GUC (rather than a temp table) keeps
  -- the assertion to a single SQL expression.
  perform set_config('app_test.unprotected_public_tables',
                     coalesce(unprotected_tables, ''),
                     true);
end$$;

select is(
  current_setting('app_test.unprotected_public_tables', true),
  '',
  'every public.* table has ENABLE + FORCE row level security '
    || '(any table listed in the actual value above is missing one or both flags)'
);

select * from finish();

rollback;
