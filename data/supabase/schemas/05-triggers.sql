-- 05-triggers.sql — updated_at, cache-clear, and cookbook image delete.
--
-- Depends on:     02-tables.sql (the tables exist);
--                 01-app-private.sql (app_private.set_updated_at());
--                 04-storage.sql (the cookbook-images bucket exists).
-- Depended on by: the Go backend implicitly. The backend MUST NOT write
--                 updated_at columns; this file owns them. The backend
--                 MUST NOT call the Storage delete API for cookbook
--                 row deletes; the trigger here owns that lifecycle
--                 (contract §6.1 integration point + ADR-0004).
-- Why it exists:  dc-04 — "Maintain updated_at with a trigger, not
--                 application code". And ADR-0004 — the cookbook image
--                 lifecycle is atomic with the row lifecycle, which
--                 requires a DB trigger because the storage delete and
--                 the row delete must commit together.
--
-- Note on transactional atomicity: storage.objects is an ordinary
-- Postgres table on the same cluster as public.cookbook_recipes, so an
-- AFTER DELETE trigger that issues a DELETE against it runs in the same
-- transaction. If the outer commit rolls back, both deletes roll back.
-- This is the contract guarantee track-data §6 R5 promises.

-- ============================================================================
-- updated_at — BEFORE UPDATE on every table that carries updated_at.
-- kitchen_messages does NOT have updated_at (append-only); no trigger.
-- ============================================================================

create trigger food_items_set_updated_at
  before update on public.food_items
  for each row execute function app_private.set_updated_at();

create trigger meal_plans_set_updated_at
  before update on public.meal_plans
  for each row execute function app_private.set_updated_at();

create trigger meal_plan_days_set_updated_at
  before update on public.meal_plan_days
  for each row execute function app_private.set_updated_at();

create trigger cookbook_recipes_set_updated_at
  before update on public.cookbook_recipes
  for each row execute function app_private.set_updated_at();

create trigger shopping_lists_set_updated_at
  before update on public.shopping_lists
  for each row execute function app_private.set_updated_at();

create trigger shopping_list_items_set_updated_at
  before update on public.shopping_list_items
  for each row execute function app_private.set_updated_at();

create trigger kitchen_conversations_set_updated_at
  before update on public.kitchen_conversations
  for each row execute function app_private.set_updated_at();


-- ============================================================================
-- Cache-clearing invariant on meal_plan_days — when meal_name changes,
-- the cached recipe_content and recipe_image_prompt are stale and must
-- be nulled. The Go backend SHOULD do this in its update helpers; this
-- trigger is defence-in-depth (contract §4.3, track-data §3.5).
-- ============================================================================

create or replace function app_private.meal_plan_days_clear_recipe_cache()
  returns trigger
  language plpgsql
as $$
begin
  -- IS DISTINCT FROM handles NULL on either side correctly. We only fire
  -- the clear when meal_name actually changes; an UPDATE that touches
  -- only notes leaves the cache alone.
  if new.meal_name is distinct from old.meal_name then
    new.recipe_content      := null;
    new.recipe_image_prompt := null;
  end if;
  return new;
end$$;

comment on function app_private.meal_plan_days_clear_recipe_cache() is
  'Defence-in-depth trigger function: nulls the recipe markdown + image-'
  'prompt cache columns when meal_name changes. The Go backend''s update '
  'helpers do this explicitly; this is the belt to that belt.';

create trigger meal_plan_days_clear_recipe_cache
  before update on public.meal_plan_days
  for each row execute function app_private.meal_plan_days_clear_recipe_cache();


-- ============================================================================
-- Cookbook delete → storage.objects delete (ADR-0004 + contract §5.6).
-- AFTER DELETE because the row must already be gone when we reach into
-- storage; if the cookbook delete is rolled back, the storage delete
-- rolls back with it (same transaction).
--
-- We only act if image_url was set — a row that never had its image
-- generated has no storage object to remove. The object key is
-- {user_id}/{id}.png, by the convention enforced by 04-storage.sql's
-- RLS policies.
-- ============================================================================

create or replace function app_private.cookbook_recipes_delete_storage_object()
  returns trigger
  language plpgsql
  security definer
  set search_path = public, storage, pg_temp
as $$
begin
  -- Guard: nothing to do if the row never had bytes uploaded.
  if old.image_url is null then
    return old;
  end if;

  -- Best-effort delete. If the storage row was already removed (a manual
  -- cleanup, a previous re-attempt) the DELETE matches zero rows and the
  -- trigger still returns OK. We do NOT raise — the cookbook row is
  -- already gone and the user-visible operation succeeded.
  delete from storage.objects
   where bucket_id = 'cookbook-images'
     and name = old.user_id::text || '/' || old.id::text || '.png';

  return old;
end$$;

comment on function app_private.cookbook_recipes_delete_storage_object() is
  'AFTER DELETE on cookbook_recipes. Removes the matching storage.objects '
  'row in the same transaction. SECURITY DEFINER so the delete bypasses '
  'the storage.objects RLS policy (which requires a JWT subject — the '
  'trigger runs in the row-owner''s transaction but RLS evaluation would '
  'still require auth.uid() to match the path prefix; SECURITY DEFINER '
  'sidesteps that).';

create trigger cookbook_recipes_delete_storage_object
  after delete on public.cookbook_recipes
  for each row execute function app_private.cookbook_recipes_delete_storage_object();
