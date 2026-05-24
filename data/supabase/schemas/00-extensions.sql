-- 00-extensions.sql — Postgres extensions required by the schema.
--
-- Depends on:     a clean Supabase Postgres 17 cluster.
-- Depended on by: every subsequent schemas/*.sql — UUID generation and the
--                 `app_private` schema's helpers assume these are present.
-- Why it exists:  CREATE EXTENSION statements must run before any object that
--                 references them. Centralising them in file 00 makes that
--                 ordering explicit; `supabase db diff` honours the alpha-
--                 sorted filename order when materialising the migration.
--
-- Notes:
--   * `pgcrypto` is enabled by Supabase by default but listed here so the
--     declarative state is self-contained.
--   * Per ADR / track-data §9 Q2 the choice of UUID v7 source is open. We
--     attempt `pg_uuidv7` (Supabase's preferred extension on PG17) inside a
--     DO block; if it isn't available the schema falls through to
--     `gen_random_uuid()` (pgcrypto), which is a documented deviation from
--     dc-04's UUIDv7 preference. The fall-back is wired by defining
--     `app_private.uuidv7()` in 01-app-private.sql — every table calls that
--     helper rather than the extension function directly, so the rest of the
--     schema does not care which path was taken.

create extension if not exists pgcrypto with schema extensions;

-- Try to enable pg_uuidv7; if it's not installable on this cluster we leave
-- it disabled and the helper in 01-app-private.sql falls back to
-- gen_random_uuid(). The DO block swallows the "extension not available"
-- error so `supabase db reset` does not abort on a fresh stack.
do $$
begin
  begin
    create extension if not exists pg_uuidv7 with schema extensions;
  exception when others then
    raise notice 'pg_uuidv7 not available on this cluster: %', sqlerrm;
  end;
end$$;
