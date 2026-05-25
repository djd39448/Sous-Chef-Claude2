-- 04_cookbook_images_storage_isolation.sql — storage.objects RLS on the
-- cookbook-images bucket scopes by path prefix matching auth.uid().
--
-- Depends on:     pgTAP extension (`create extension pgtap`);
--                 supabase/schemas/* applied (via `supabase db reset`).
-- Depended on by: CI's `make test` target. The track-data §5 task 18
--                 acceptance check requires (d) Storage bucket cross-
--                 user object access; this file is that proof.
-- Why it exists:  04-storage.sql declares four policies on storage.objects
--                 filtered `bucket_id = 'cookbook-images'` and scoped by
--                 `(storage.foldername(name))[1] = auth.uid()::text`.
--                 The CFO test (01) exercises public-schema RLS only —
--                 this test exercises Supabase's storage.objects RLS,
--                 which is a *different* PostgreSQL table with its own
--                 policy layer. Per ADR-0004 these policies are the only
--                 thing standing between user A and user B's cookbook
--                 image bytes; a regression here is a data leak (track-
--                 data §8 R1).
--
-- Test strategy: as the storage superuser, insert two synthetic
-- storage.objects rows under different user-id path prefixes. Then under
-- the authenticated role, impersonate each user in turn and assert path-
-- prefix scoping holds for SELECT / INSERT / UPDATE / DELETE.

begin;

select plan(8);

-- ----------------------------------------------------------------------------
-- Fixture: two users + two storage.objects rows, one per user prefix.
-- storage.objects.owner expects a uuid; storage.objects.bucket_id matches
-- our bucket. We use the (id, bucket_id, name) columns directly — the
-- Supabase Storage API normally sets owner/metadata, but for an RLS
-- visibility test the path is what matters.
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

-- Bucket is created by 04-storage.sql; the on-conflict upsert there is
-- idempotent. We do not re-create it here.

-- Two synthetic objects. The object key follows the convention
-- {user_id}/{cookbook_recipe_id}.png — only the leading path segment
-- matters for the RLS check (the trailing segment is opaque to
-- storage.foldername()[1]).
insert into storage.objects (id, bucket_id, name, owner)
values
  (gen_random_uuid(),
   'cookbook-images',
   '11111111-1111-1111-1111-111111111111/recipe-a.png',
   '11111111-1111-1111-1111-111111111111'),
  (gen_random_uuid(),
   'cookbook-images',
   '22222222-2222-2222-2222-222222222222/recipe-b.png',
   '22222222-2222-2222-2222-222222222222');

-- ----------------------------------------------------------------------------
-- Impersonate user A.
-- ----------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

-- 1. User A sees exactly one cookbook-images object — their own.
select is(
  (select count(*)::int from storage.objects
     where bucket_id = 'cookbook-images'),
  1,
  'user A sees exactly 1 cookbook-images object (their own)'
);

-- 2. The visible object is under user A's prefix.
select is(
  (select (storage.foldername(name))[1] from storage.objects
     where bucket_id = 'cookbook-images' limit 1),
  '11111111-1111-1111-1111-111111111111',
  'user A''s visible object is under their own user_id path prefix'
);

-- 3. User A cannot SELECT user B's object filtered by name. The RLS
-- USING clause filters it out — no row is returned.
select is(
  (select count(*)::int from storage.objects
     where bucket_id = 'cookbook-images'
       and name = '22222222-2222-2222-2222-222222222222/recipe-b.png'),
  0,
  'user A cannot SELECT a cookbook-images object under user B''s prefix'
);

-- 4. User A cannot INSERT an object under user B's prefix (WITH CHECK
-- on cookbook_images_insert_own enforces the leading segment match).
select throws_ok(
  $$ insert into storage.objects (id, bucket_id, name, owner)
     values (gen_random_uuid(),
             'cookbook-images',
             '22222222-2222-2222-2222-222222222222/forged.png',
             '11111111-1111-1111-1111-111111111111') $$,
  '42501',
  'new row violates row-level security policy for table "objects"',
  'user A cannot INSERT a cookbook-images object under user B''s prefix'
);

-- ----------------------------------------------------------------------------
-- Switch to user B.
-- ----------------------------------------------------------------------------

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

-- 5. User B sees exactly one cookbook-images object — their own.
select is(
  (select count(*)::int from storage.objects
     where bucket_id = 'cookbook-images'),
  1,
  'user B sees exactly 1 cookbook-images object (their own)'
);

-- 6. User B's UPDATE against user A's object hits zero rows (USING
-- clause filters it out). The proof: switch back to user A and confirm
-- the name still matches the original.
update storage.objects
   set name = '11111111-1111-1111-1111-111111111111/tampered.png'
 where bucket_id = 'cookbook-images'
   and name = '11111111-1111-1111-1111-111111111111/recipe-a.png';

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

select is(
  (select count(*)::int from storage.objects
     where bucket_id = 'cookbook-images'
       and name = '11111111-1111-1111-1111-111111111111/recipe-a.png'),
  1,
  'user B''s UPDATE attempt against user A''s object matched zero rows'
);

-- 7. Same for DELETE.
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

delete from storage.objects
 where bucket_id = 'cookbook-images'
   and name = '11111111-1111-1111-1111-111111111111/recipe-a.png';

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

select is(
  (select count(*)::int from storage.objects
     where bucket_id = 'cookbook-images'
       and name = '11111111-1111-1111-1111-111111111111/recipe-a.png'),
  1,
  'user B''s DELETE attempt against user A''s object matched zero rows'
);

-- 8. User A CAN INSERT under their own prefix (positive control: the
-- policy is not a blanket deny).
insert into storage.objects (id, bucket_id, name, owner)
values (gen_random_uuid(),
        'cookbook-images',
        '11111111-1111-1111-1111-111111111111/recipe-c.png',
        '11111111-1111-1111-1111-111111111111');

select is(
  (select count(*)::int from storage.objects
     where bucket_id = 'cookbook-images'
       and name = '11111111-1111-1111-1111-111111111111/recipe-c.png'),
  1,
  'user A CAN INSERT a cookbook-images object under their own prefix'
);

select * from finish();

rollback;
