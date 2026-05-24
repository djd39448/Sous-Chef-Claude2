-- 03-rls.sql — Row-Level Security: enable + force + per-operation policies.
--
-- Depends on:     02-tables.sql (the tables exist);
--                 01-app-private.sql (the owns_* helpers).
-- Depended on by: 06-tests/* (pgTAP cross-user assertions). The Go
--                 backend's correctness depends on these policies — the
--                 backend connects as the `authenticated` role and never
--                 with the service-role key (ADR-0011), so every read
--                 and write goes through RLS.
-- Why it exists:  dc-04 mandates RLS default-on, FORCE on every table in
--                 an exposed schema, one policy per operation, all wrapped
--                 with (select auth.uid()) so the JWT subselect runs once
--                 per statement. This file is that policy ledger.
--
-- Pattern for owner-scoped tables (food_items, meal_plans,
-- cookbook_recipes, shopping_lists, kitchen_conversations):
--   * Four policies: SELECT / INSERT / UPDATE / DELETE.
--   * Each policy: TO authenticated, USING/ WITH CHECK on
--     user_id = (select auth.uid()).
--
-- Pattern for ownership-via-parent tables (meal_plan_days,
-- shopping_list_items, kitchen_messages):
--   * Same four policies (kitchen_messages is the append-only exception
--     — INSERT + SELECT only).
--   * Each policy calls the matching app_private.owns_*(parent_id) helper
--     so PostgREST does not need to know about the parent table's RLS.
--   * The helper is SECURITY DEFINER + STABLE, which means Postgres
--     evaluates it once per statement, not once per row, and bypasses
--     RLS recursion on the parent table.

-- ============================================================================
-- Enable + force RLS on every table. dc-04: ENABLE is not enough — without
-- FORCE, the table owner bypasses RLS, which silently breaks the model.
-- ============================================================================

alter table public.food_items             enable row level security;
alter table public.food_items             force  row level security;
alter table public.meal_plans             enable row level security;
alter table public.meal_plans             force  row level security;
alter table public.meal_plan_days         enable row level security;
alter table public.meal_plan_days         force  row level security;
alter table public.cookbook_recipes       enable row level security;
alter table public.cookbook_recipes       force  row level security;
alter table public.shopping_lists         enable row level security;
alter table public.shopping_lists         force  row level security;
alter table public.shopping_list_items    enable row level security;
alter table public.shopping_list_items    force  row level security;
alter table public.kitchen_conversations  enable row level security;
alter table public.kitchen_conversations  force  row level security;
alter table public.kitchen_messages       enable row level security;
alter table public.kitchen_messages       force  row level security;

-- ============================================================================
-- food_items — owner-scoped.
-- ============================================================================

create policy food_items_select_own on public.food_items
  for select to authenticated
  using (user_id = (select auth.uid()));
comment on policy food_items_select_own on public.food_items is
  'Caller reads only their own CFO rows.';

create policy food_items_insert_own on public.food_items
  for insert to authenticated
  with check (user_id = (select auth.uid()));
comment on policy food_items_insert_own on public.food_items is
  'Caller inserts only rows attributed to themselves. user_id is taken '
  'from auth.uid() by the Go backend (contract §2) — the policy prevents '
  'a forged user_id from a buggy code path.';

create policy food_items_update_own on public.food_items
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
comment on policy food_items_update_own on public.food_items is
  'Caller updates only their own rows AND cannot change user_id to '
  'someone else''s id (the WITH CHECK clause).';

create policy food_items_delete_own on public.food_items
  for delete to authenticated
  using (user_id = (select auth.uid()));
comment on policy food_items_delete_own on public.food_items is
  'Caller deletes only their own rows.';


-- ============================================================================
-- meal_plans — owner-scoped.
-- ============================================================================

create policy meal_plans_select_own on public.meal_plans
  for select to authenticated
  using (user_id = (select auth.uid()));
comment on policy meal_plans_select_own on public.meal_plans is
  'Caller reads only their own weekly plans.';

create policy meal_plans_insert_own on public.meal_plans
  for insert to authenticated
  with check (user_id = (select auth.uid()));
comment on policy meal_plans_insert_own on public.meal_plans is
  'Caller inserts only plans attributed to themselves.';

create policy meal_plans_update_own on public.meal_plans
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
comment on policy meal_plans_update_own on public.meal_plans is
  'Caller updates only their own plans; cannot reattribute to another user.';

create policy meal_plans_delete_own on public.meal_plans
  for delete to authenticated
  using (user_id = (select auth.uid()));
comment on policy meal_plans_delete_own on public.meal_plans is
  'Caller deletes only their own plans. CASCADE removes their meal_plan_days.';


-- ============================================================================
-- meal_plan_days — ownership flows through meal_plans.user_id.
-- Uses app_private.owns_meal_plan() so PostgREST does not need a SELECT
-- policy on meal_plans to evaluate this check.
-- ============================================================================

create policy meal_plan_days_select_own on public.meal_plan_days
  for select to authenticated
  using (app_private.owns_meal_plan(meal_plan_id));
comment on policy meal_plan_days_select_own on public.meal_plan_days is
  'Caller reads only days under a meal_plan they own.';

create policy meal_plan_days_insert_own on public.meal_plan_days
  for insert to authenticated
  with check (app_private.owns_meal_plan(meal_plan_id));
comment on policy meal_plan_days_insert_own on public.meal_plan_days is
  'Caller inserts only into a meal_plan they own.';

create policy meal_plan_days_update_own on public.meal_plan_days
  for update to authenticated
  using (app_private.owns_meal_plan(meal_plan_id))
  with check (app_private.owns_meal_plan(meal_plan_id));
comment on policy meal_plan_days_update_own on public.meal_plan_days is
  'Caller updates only days under plans they own, and cannot move a day '
  'to another user''s plan (the WITH CHECK clause re-verifies the parent).';

create policy meal_plan_days_delete_own on public.meal_plan_days
  for delete to authenticated
  using (app_private.owns_meal_plan(meal_plan_id));
comment on policy meal_plan_days_delete_own on public.meal_plan_days is
  'Caller deletes only days under plans they own.';


-- ============================================================================
-- cookbook_recipes — owner-scoped.
-- ============================================================================

create policy cookbook_recipes_select_own on public.cookbook_recipes
  for select to authenticated
  using (user_id = (select auth.uid()));
comment on policy cookbook_recipes_select_own on public.cookbook_recipes is
  'Caller reads only their own cookbook recipes.';

create policy cookbook_recipes_insert_own on public.cookbook_recipes
  for insert to authenticated
  with check (user_id = (select auth.uid()));
comment on policy cookbook_recipes_insert_own on public.cookbook_recipes is
  'Caller inserts only recipes attributed to themselves.';

create policy cookbook_recipes_update_own on public.cookbook_recipes
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
comment on policy cookbook_recipes_update_own on public.cookbook_recipes is
  'Caller updates only their own recipes.';

create policy cookbook_recipes_delete_own on public.cookbook_recipes
  for delete to authenticated
  using (user_id = (select auth.uid()));
comment on policy cookbook_recipes_delete_own on public.cookbook_recipes is
  'Caller deletes only their own recipes. The 05-triggers.sql delete '
  'trigger then removes the cookbook-images storage object atomically.';


-- ============================================================================
-- shopping_lists — owner-scoped.
-- ============================================================================

create policy shopping_lists_select_own on public.shopping_lists
  for select to authenticated
  using (user_id = (select auth.uid()));
comment on policy shopping_lists_select_own on public.shopping_lists is
  'Caller reads only their own shopping lists.';

create policy shopping_lists_insert_own on public.shopping_lists
  for insert to authenticated
  with check (user_id = (select auth.uid()));
comment on policy shopping_lists_insert_own on public.shopping_lists is
  'Caller inserts only lists attributed to themselves.';

create policy shopping_lists_update_own on public.shopping_lists
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
comment on policy shopping_lists_update_own on public.shopping_lists is
  'Caller updates only their own lists.';

create policy shopping_lists_delete_own on public.shopping_lists
  for delete to authenticated
  using (user_id = (select auth.uid()));
comment on policy shopping_lists_delete_own on public.shopping_lists is
  'Caller deletes only their own lists. CASCADE removes their items.';


-- ============================================================================
-- shopping_list_items — ownership flows through shopping_lists.user_id.
-- ============================================================================

create policy shopping_list_items_select_own on public.shopping_list_items
  for select to authenticated
  using (app_private.owns_shopping_list(shopping_list_id));
comment on policy shopping_list_items_select_own on public.shopping_list_items is
  'Caller reads only items under a list they own.';

create policy shopping_list_items_insert_own on public.shopping_list_items
  for insert to authenticated
  with check (app_private.owns_shopping_list(shopping_list_id));
comment on policy shopping_list_items_insert_own on public.shopping_list_items is
  'Caller inserts only into a list they own.';

create policy shopping_list_items_update_own on public.shopping_list_items
  for update to authenticated
  using (app_private.owns_shopping_list(shopping_list_id))
  with check (app_private.owns_shopping_list(shopping_list_id));
comment on policy shopping_list_items_update_own on public.shopping_list_items is
  'Caller updates only items under lists they own. The check-off PATCH '
  'endpoint (contract §5.4) lands here.';

create policy shopping_list_items_delete_own on public.shopping_list_items
  for delete to authenticated
  using (app_private.owns_shopping_list(shopping_list_id));
comment on policy shopping_list_items_delete_own on public.shopping_list_items is
  'Caller deletes only items under lists they own. The clear-checked '
  'endpoint (ADR-0007) lands here.';


-- ============================================================================
-- kitchen_conversations — owner-scoped.
-- ============================================================================

create policy kitchen_conversations_select_own on public.kitchen_conversations
  for select to authenticated
  using (user_id = (select auth.uid()));
comment on policy kitchen_conversations_select_own on public.kitchen_conversations is
  'Caller reads only their own conversations.';

create policy kitchen_conversations_insert_own on public.kitchen_conversations
  for insert to authenticated
  with check (user_id = (select auth.uid()));
comment on policy kitchen_conversations_insert_own on public.kitchen_conversations is
  'Caller inserts only conversations attributed to themselves.';

create policy kitchen_conversations_update_own on public.kitchen_conversations
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
comment on policy kitchen_conversations_update_own on public.kitchen_conversations is
  'Caller updates only their own conversations (e.g. title auto-set).';

create policy kitchen_conversations_delete_own on public.kitchen_conversations
  for delete to authenticated
  using (user_id = (select auth.uid()));
comment on policy kitchen_conversations_delete_own on public.kitchen_conversations is
  'Caller deletes only their own conversations. CASCADE removes messages.';


-- ============================================================================
-- kitchen_messages — APPEND-ONLY. Only INSERT and SELECT policies are
-- declared. UPDATE and DELETE attempts by `authenticated` are rejected by
-- "no policy matched" (RLS default-deny). Cascade-delete from a parent
-- conversation still works because FK cascades do not consult RLS.
-- Contract §4.6 calls this out explicitly.
-- ============================================================================

create policy kitchen_messages_select_own on public.kitchen_messages
  for select to authenticated
  using (app_private.owns_kitchen_conversation(conversation_id));
comment on policy kitchen_messages_select_own on public.kitchen_messages is
  'Caller reads only messages under conversations they own.';

create policy kitchen_messages_insert_own on public.kitchen_messages
  for insert to authenticated
  with check (app_private.owns_kitchen_conversation(conversation_id));
comment on policy kitchen_messages_insert_own on public.kitchen_messages is
  'Caller inserts only into conversations they own. No UPDATE or DELETE '
  'policy is declared — kitchen_messages is append-only per contract §4.6.';
