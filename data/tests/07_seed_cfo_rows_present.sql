-- 07_seed_cfo_rows_present.sql — after `make reset`, the test user has
-- exactly 5 food_items rows with usage_context.role = 'inventory'.
--
-- Depends on:     pgTAP extension (`create extension pgtap`);
--                 supabase/schemas/* applied AND seed.sql applied (via
--                 `make reset`, which sets PGOPTIONS so the seed
--                 guard passes).
-- Depended on by: CI's `make test` target. The backend track's
--                 GET /api/kitchen/ingredients integration tests depend
--                 on this data being present; a regression in seed.sql
--                 (FORCE-RLS dance broken, on-conflict columns wrong,
--                 etc.) would silently zero out the backend's smoke
--                 test data.
-- Why it exists:  seed.sql is dev-only and easy to break invisibly —
--                 the FORCE-RLS dance, the JSONB shape conformance to
--                 contract §4.1, and the canonical_name/role uniqueness
--                 constraints all interact. This test pins the
--                 *observable outcome* (5 rows, all inventory, varied
--                 categories and statuses) so any breakage shows up
--                 immediately in CI.
--
-- Note: unlike the RLS-isolation tests, this one runs as the postgres
-- superuser (the same context that `make reset` loads seed.sql under)
-- — we are asserting facts about the seeded state, not RLS behavior.

begin;

select plan(7);

-- 1. The test user exists.
select is(
  (select count(*)::int from auth.users
     where id = '00000000-0000-0000-0000-000000000001'),
  1,
  'seed test user (00000000-0000-0000-0000-000000000001) exists'
);

-- 2. The test user owns exactly 5 food_items rows.
select is(
  (select count(*)::int from public.food_items
     where user_id = '00000000-0000-0000-0000-000000000001'),
  5,
  'test user owns exactly 5 food_items rows'
);

-- 3. All 5 rows are inventory-role (the role the
-- GET /api/kitchen/ingredients endpoint filters by).
select is(
  (select count(*)::int from public.food_items
     where user_id = '00000000-0000-0000-0000-000000000001'
       and usage_context->>'role' = 'inventory'),
  5,
  'all 5 seeded rows have usage_context.role = ''inventory'''
);

-- 4. Variety across categories — at least one of produce, dairy, meat.
-- The contract's category.primary CHECK admits 9 values; the seed
-- intentionally covers three for the backend's category-grouping logic.
select is(
  (select count(distinct category->>'primary')::int from public.food_items
     where user_id = '00000000-0000-0000-0000-000000000001'),
  3,
  'seed covers 3 distinct category.primary values (produce, dairy, meat)'
);

-- 5. Variety across inventory_state.status — confirmed, likely, unknown
-- (out is reserved for the remove-action path). The backend's chat-
-- context filter inspects this column.
select is(
  (select count(distinct inventory_state->>'status')::int from public.food_items
     where user_id = '00000000-0000-0000-0000-000000000001'),
  3,
  'seed covers 3 distinct inventory_state.status values'
);

-- 6. At least one row has a structured quantity (amount + unit). This
-- exercises the wire shape contract §4.2 documents.
select ok(
  (select count(*)::int from public.food_items
     where user_id = '00000000-0000-0000-0000-000000000001'
       and quantity is not null
       and quantity ? 'amount'
       and quantity ? 'unit') >= 1,
  'at least one seeded row has a structured quantity (amount + unit)'
);

-- 7. At least one row has a null quantity (the "I have this but
-- don't know how much" case the AI tools produce).
select ok(
  (select count(*)::int from public.food_items
     where user_id = '00000000-0000-0000-0000-000000000001'
       and quantity is null) >= 1,
  'at least one seeded row has null quantity (presence-only entry)'
);

select * from finish();

rollback;
