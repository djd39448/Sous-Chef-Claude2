-- 01-app-private.sql — the `app_private` schema and its shared helpers.
--
-- Depends on:     00-extensions.sql (pgcrypto; optionally pg_uuidv7).
-- Depended on by: 02-tables.sql (every table's PK default and every table's
--                 updated_at trigger references functions defined here);
--                 03-rls.sql (ownership-via-parent policies call the
--                 SECURITY DEFINER helpers below).
-- Why it exists:  dc-04 requires multi-table RLS logic to live in a
--                 SECURITY DEFINER function in a non-exposed schema; this
--                 file declares that schema and the helpers used by both
--                 the RLS policies and the table triggers. Keeping them
--                 here means `public` carries only the user-visible schema.
--
-- Exposure note: PostgREST exposes the schemas listed in
-- `config.toml#[api].schemas`; `app_private` is deliberately omitted there
-- so its functions are unreachable over HTTP. The Go backend connects to
-- Postgres directly (ADR-0011) and never needs to call these functions
-- itself — they are invoked only by RLS policies and triggers.

create schema if not exists app_private;
revoke all on schema app_private from public;
revoke all on schema app_private from anon, authenticated;
grant usage on schema app_private to authenticated;

-- uuidv7() wrapper — prefers the extension when present, otherwise falls
-- back to gen_random_uuid(). dc-04 prefers UUIDv7 because the embedded
-- timestamp keeps inserts B-tree ordered; the v4 fallback is documented as
-- a known deviation (track-data §9 Q2) and is acceptable for v1.
create or replace function app_private.uuidv7()
  returns uuid
  language plpgsql
  volatile
as $$
begin
  -- pg_uuidv7 exposes `uuid_generate_v7()` in the `extensions` schema on
  -- Supabase. We probe for it at call-time so the schema is portable
  -- across clusters that have the extension and clusters that don't.
  if to_regprocedure('extensions.uuid_generate_v7()') is not null then
    return (select extensions.uuid_generate_v7());
  end if;
  return gen_random_uuid();
end$$;

comment on function app_private.uuidv7() is
  'Primary-key generator. Returns a UUIDv7 if pg_uuidv7 is installed; otherwise '
  'gen_random_uuid() (v4) as a fall-back. Every table''s PK default calls this.';

-- set_updated_at() — BEFORE UPDATE trigger function for every table that
-- carries an updated_at column. dc-04 mandates that updated_at is
-- maintained by a trigger, not by application code.
create or replace function app_private.set_updated_at()
  returns trigger
  language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end$$;

comment on function app_private.set_updated_at() is
  'BEFORE UPDATE trigger. Stamps updated_at on every row mutation. The Go '
  'backend MUST NOT write to updated_at columns — this trigger owns them.';

-- owns_meal_plan() — used by meal_plan_days RLS policies. Returns true
-- iff the caller (auth.uid()) owns the meal_plans row identified by
-- _meal_plan_id. SECURITY DEFINER lets the policy peek at meal_plans
-- without triggering a circular RLS check on that table.
create or replace function app_private.owns_meal_plan(_meal_plan_id uuid)
  returns boolean
  language sql
  stable
  security definer
  set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.meal_plans mp
    where mp.id = _meal_plan_id
      and mp.user_id = (select auth.uid())
  );
$$;

comment on function app_private.owns_meal_plan(uuid) is
  'RLS helper for meal_plan_days. Returns true iff the JWT caller owns the '
  'parent meal_plan. SECURITY DEFINER + STABLE so each statement evaluates '
  'it once and bypasses RLS recursion (per dc-04 §RLS).';

-- owns_shopping_list() — used by shopping_list_items RLS policies.
create or replace function app_private.owns_shopping_list(_shopping_list_id uuid)
  returns boolean
  language sql
  stable
  security definer
  set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.shopping_lists sl
    where sl.id = _shopping_list_id
      and sl.user_id = (select auth.uid())
  );
$$;

comment on function app_private.owns_shopping_list(uuid) is
  'RLS helper for shopping_list_items. Same pattern as owns_meal_plan().';

-- owns_kitchen_conversation() — used by kitchen_messages RLS policies.
create or replace function app_private.owns_kitchen_conversation(_conversation_id uuid)
  returns boolean
  language sql
  stable
  security definer
  set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.kitchen_conversations kc
    where kc.id = _conversation_id
      and kc.user_id = (select auth.uid())
  );
$$;

comment on function app_private.owns_kitchen_conversation(uuid) is
  'RLS helper for kitchen_messages. Same pattern as owns_meal_plan(). '
  'kitchen_messages is append-only — only the INSERT and SELECT policies '
  'reference this; there are no UPDATE / DELETE policies (contract §4.6).';

-- Grant execute on the helpers to the authenticated role; revoke from
-- anon and public. The functions never trust an argument; identity is
-- always read from auth.uid().
revoke all on function app_private.uuidv7()                              from public;
revoke all on function app_private.set_updated_at()                      from public;
revoke all on function app_private.owns_meal_plan(uuid)                  from public;
revoke all on function app_private.owns_shopping_list(uuid)              from public;
revoke all on function app_private.owns_kitchen_conversation(uuid)       from public;

grant execute on function app_private.uuidv7()                              to authenticated;
grant execute on function app_private.owns_meal_plan(uuid)                  to authenticated;
grant execute on function app_private.owns_shopping_list(uuid)              to authenticated;
grant execute on function app_private.owns_kitchen_conversation(uuid)       to authenticated;
-- set_updated_at() is only ever called from triggers — no role needs EXECUTE.
