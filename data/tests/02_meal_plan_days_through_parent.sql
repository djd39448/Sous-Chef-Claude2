-- 02_meal_plan_days_through_parent.sql — meal_plan_days ownership flows
-- through meal_plans.user_id via the app_private.owns_meal_plan helper.
--
-- Depends on:     pgTAP extension (`create extension pgtap`);
--                 supabase/schemas/* applied (via `supabase db reset`).
-- Depended on by: CI's `make test` target. The track-data §5 task 18
--                 acceptance check requires (b) meal_plan_days through-
--                 parent isolation; this file is that proof.
-- Why it exists:  meal_plan_days does NOT carry user_id; ownership is
--                 mediated by the SECURITY DEFINER helper
--                 app_private.owns_meal_plan(meal_plan_id). A regression
--                 in the helper or the policy would let user A read or
--                 mutate rows under user B's plans. The CFO test
--                 (01_rls_cross_user_isolation.sql) does not exercise
--                 the through-parent pattern at all — that is this
--                 test's whole job.
--
-- Test strategy: insert two users + one meal_plan per user + one
-- meal_plan_days row per plan (as superuser during fixture setup).
-- Then SET LOCAL request.jwt.claim.sub to each user in turn and assert
-- SELECT/UPDATE/DELETE visibility and INSERT enforcement.

begin;

select plan(8);

-- ----------------------------------------------------------------------------
-- Fixture: two users; one meal_plan + one meal_plan_days row each.
-- ----------------------------------------------------------------------------

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                        created_at, updated_at)
values
  ('11111111-1111-1111-1111-111111111111',
   '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'user-a@test.invalid', '',
   now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('22222222-2222-2222-2222-222222222222',
   '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'user-b@test.invalid', '',
   now(), '{}'::jsonb, '{}'::jsonb, now(), now())
on conflict (id) do nothing;

-- Two meal plans, deterministic ids so the test can reference them by
-- literal UUID. 2026-05-25 is a Monday (passes week_start_is_monday).
insert into public.meal_plans (id, user_id, week_start_date)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '11111111-1111-1111-1111-111111111111',
   '2026-05-25'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   '22222222-2222-2222-2222-222222222222',
   '2026-05-25');

-- One day-row per plan.
insert into public.meal_plan_days (meal_plan_id, day_of_week, meal_name)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 1, 'User A Monday Soup'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 1, 'User B Monday Stew');

-- ----------------------------------------------------------------------------
-- Impersonate user A; assert SELECT, UPDATE, and DELETE all filter to A's
-- meal_plan_days rows. The SECURITY DEFINER helper owns_meal_plan() is
-- under test transitively: its return-value drives every policy.
-- ----------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

-- 1. User A sees exactly one meal_plan_days row — under their plan.
select is(
  (select count(*)::int from public.meal_plan_days),
  1,
  'user A sees exactly 1 meal_plan_days row (under their own plan)'
);

-- 2. The visible row is user A's.
select is(
  (select meal_name from public.meal_plan_days limit 1),
  'User A Monday Soup',
  'user A''s visible meal_plan_days row is their Monday Soup'
);

-- 3. User A cannot SELECT user B's day-row by parent id.
select is(
  (select count(*)::int from public.meal_plan_days
    where meal_plan_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  0,
  'user A cannot SELECT a meal_plan_days row under user B''s plan'
);

-- 4. User A cannot INSERT a day-row into user B's plan.
-- The WITH CHECK on meal_plan_days_insert_own calls owns_meal_plan(),
-- which returns false → 42501.
select throws_ok(
  $$ insert into public.meal_plan_days
       (meal_plan_id, day_of_week, meal_name)
     values
       ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 2, 'Forged Tuesday') $$,
  '42501',
  'new row violates row-level security policy for table "meal_plan_days"',
  'user A cannot INSERT a meal_plan_days row under user B''s plan'
);

-- ----------------------------------------------------------------------------
-- Switch to user B; assert the UPDATE and DELETE attempts against user A's
-- day-row match zero rows (USING clause filters them out, no error fires).
-- ----------------------------------------------------------------------------

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

-- 5. User B's UPDATE against user A's day-row hits zero rows. The proof:
-- after running the UPDATE, switch back to user A and the row is
-- unchanged.
update public.meal_plan_days
   set meal_name = 'Hijacked'
 where meal_plan_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

-- 6. User B's DELETE against user A's day-row also hits zero rows.
delete from public.meal_plan_days
 where meal_plan_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

-- Switch back to user A; the row should still read as 'User A Monday Soup'.
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

select is(
  (select meal_name from public.meal_plan_days
     where meal_plan_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'User A Monday Soup',
  'user B''s UPDATE attempt against user A''s day-row matched zero rows'
);

select is(
  (select count(*)::int from public.meal_plan_days
     where meal_plan_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  1,
  'user B''s DELETE attempt against user A''s day-row matched zero rows'
);

-- 7. User A can still UPDATE their own row — confirms the policy is not
-- a blanket deny; the USING clause is correctly identity-scoped.
update public.meal_plan_days
   set notes = 'updated by owner'
 where meal_plan_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

select is(
  (select notes from public.meal_plan_days
     where meal_plan_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'updated by owner',
  'user A can UPDATE their own meal_plan_days row (positive control)'
);

-- 8. owns_meal_plan() returns false for a plan the caller does not own.
-- Direct assertion on the helper closes the loop — the policy is only
-- correct insofar as the helper is.
select is(
  app_private.owns_meal_plan('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  false,
  'app_private.owns_meal_plan() returns false for a plan owned by another user'
);

select * from finish();

rollback;
