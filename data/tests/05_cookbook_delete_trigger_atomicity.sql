-- 05_cookbook_delete_trigger_atomicity.sql — the AFTER DELETE trigger
-- on public.cookbook_recipes evicts the matching storage.objects row in
-- the same transaction; a rollback leaves both intact.
--
-- Depends on:     pgTAP extension (`create extension pgtap`);
--                 supabase/schemas/* applied (via `supabase db reset`).
-- Depended on by: CI's `make test` target. The track-data §5 task 18
--                 acceptance check requires (e) cookbook delete-trigger
--                 atomicity; this file is that proof.
-- Why it exists:  05-triggers.sql's cookbook_recipes_delete_storage_object
--                 trigger is the ONLY mechanism that prevents orphan PNGs
--                 in Supabase Storage when a cookbook row is deleted
--                 (track-data §6.3, §8 R5). The contract §5.6 calls out
--                 atomicity explicitly — the storage row and the cookbook
--                 row commit (or rollback) together. A non-atomic trigger
--                 (one that called the Storage REST API, say) would leave
--                 an orphan object on rollback. This test pins the
--                 transactional contract.
--
-- Test strategy: as superuser, seed a cookbook_recipes row + a matching
-- storage.objects row at the convention path. Assert both exist; delete
-- the cookbook row; assert the storage row is also gone. Then, in a
-- *second* transaction with an explicit rollback, repeat the seed +
-- delete + raise-exception cycle and assert nothing was actually removed
-- (the trigger fired but its effect was rolled back together with the
-- outer delete).

begin;

select plan(6);

-- ----------------------------------------------------------------------------
-- Fixture: one user + one cookbook recipe with an image_url + one
-- matching storage.objects row.
-- ----------------------------------------------------------------------------

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                        created_at, updated_at)
values
  ('11111111-1111-1111-1111-111111111111',
   '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'user-a@test.invalid', '',
   now(), '{}'::jsonb, '{}'::jsonb, now(), now())
on conflict (id) do nothing;

insert into public.cookbook_recipes (id, user_id, title, content, image_prompt, image_url)
values
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
   '11111111-1111-1111-1111-111111111111',
   'Test Recipe',
   '# Test Recipe\n\nMarkdown content.',
   'a test prompt',
   'https://example.invalid/storage/v1/object/public/cookbook-images/'
     || '11111111-1111-1111-1111-111111111111/eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee.png');

-- The matching storage row. The key follows the trigger's expected
-- convention: {user_id}/{cookbook_recipe_id}.png. If the trigger looks
-- elsewhere, this row will not be removed and the test fails.
insert into storage.objects (id, bucket_id, name, owner)
values (gen_random_uuid(),
        'cookbook-images',
        '11111111-1111-1111-1111-111111111111/'
          || 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee.png',
        '11111111-1111-1111-1111-111111111111');

-- 1. Pre-delete: both rows exist (positive control on the fixture).
select is(
  (select count(*)::int from public.cookbook_recipes
     where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'),
  1,
  'pre-delete: cookbook_recipes row exists'
);

select is(
  (select count(*)::int from storage.objects
     where bucket_id = 'cookbook-images'
       and name = '11111111-1111-1111-1111-111111111111/'
         || 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee.png'),
  1,
  'pre-delete: matching storage.objects row exists'
);

-- ----------------------------------------------------------------------------
-- Happy path: a successful delete removes both rows in the same transaction.
-- ----------------------------------------------------------------------------

delete from public.cookbook_recipes
 where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';

-- 2. Post-delete: cookbook row gone (sanity).
select is(
  (select count(*)::int from public.cookbook_recipes
     where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'),
  0,
  'post-delete: cookbook_recipes row removed by the DELETE statement'
);

-- 3. Post-delete: matching storage.objects row also gone — the AFTER
-- DELETE trigger fired in the same transaction.
select is(
  (select count(*)::int from storage.objects
     where bucket_id = 'cookbook-images'
       and name = '11111111-1111-1111-1111-111111111111/'
         || 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee.png'),
  0,
  'post-delete: storage.objects row removed by the AFTER DELETE trigger'
);

-- ----------------------------------------------------------------------------
-- Rollback path: re-seed and then deliberately abort the transaction
-- mid-flight via a savepoint + raise exception. Both rows must remain
-- intact — the trigger ran but its side-effect rolled back with the
-- outer DELETE.
--
-- Note: pgTAP runs the whole file inside a single transaction that
-- ROLLBACK at the end. To test the rollback semantic we use a SAVEPOINT,
-- raise inside it, and ROLLBACK TO the savepoint — same transactional
-- semantics, no need for an outer COMMIT. (A trigger-driven storage
-- delete that escaped the transaction — e.g. via a REST call to the
-- Storage API — would NOT be undone by ROLLBACK TO. The pure-SQL
-- trigger here is the contract guarantee, and this savepoint pattern
-- is its smoke test.)
-- ----------------------------------------------------------------------------

-- Re-seed for the rollback experiment.
insert into public.cookbook_recipes (id, user_id, title, content, image_prompt, image_url)
values
  ('ffffffff-ffff-ffff-ffff-ffffffffffff',
   '11111111-1111-1111-1111-111111111111',
   'Rollback Recipe',
   '# Rollback Recipe',
   'rollback prompt',
   'https://example.invalid/storage/v1/object/public/cookbook-images/'
     || '11111111-1111-1111-1111-111111111111/ffffffff-ffff-ffff-ffff-ffffffffffff.png');

insert into storage.objects (id, bucket_id, name, owner)
values (gen_random_uuid(),
        'cookbook-images',
        '11111111-1111-1111-1111-111111111111/'
          || 'ffffffff-ffff-ffff-ffff-ffffffffffff.png',
        '11111111-1111-1111-1111-111111111111');

savepoint before_delete;

do $$
begin
  delete from public.cookbook_recipes
   where id = 'ffffffff-ffff-ffff-ffff-ffffffffffff';
  -- Deliberately abort *after* the DELETE has fired the trigger. If
  -- the trigger's storage.objects DELETE is genuinely in the same
  -- transaction, this RAISE rolls both back.
  raise exception 'deliberate rollback';
end$$;

-- The DO block raised, which aborts the inner subtransaction at this
-- savepoint level. Roll back to before the delete.
rollback to savepoint before_delete;

-- 4. After rollback: cookbook row still present.
select is(
  (select count(*)::int from public.cookbook_recipes
     where id = 'ffffffff-ffff-ffff-ffff-ffffffffffff'),
  1,
  'post-rollback: cookbook_recipes row was preserved'
);

-- 5. After rollback: storage row still present (the trigger fired
-- inside the aborted DELETE; rollback undid both).
select is(
  (select count(*)::int from storage.objects
     where bucket_id = 'cookbook-images'
       and name = '11111111-1111-1111-1111-111111111111/'
         || 'ffffffff-ffff-ffff-ffff-ffffffffffff.png'),
  1,
  'post-rollback: storage.objects row was preserved (trigger atomic with outer txn)'
);

-- 6. A cookbook row with NULL image_url: deleting it does NOT raise an
-- error and does NOT remove any storage object (the trigger's NULL
-- guard, 05-triggers.sql lines 109-111).
insert into public.cookbook_recipes (id, user_id, title, content)
values
  ('aaaaaaaa-1111-2222-3333-444444444444',
   '11111111-1111-1111-1111-111111111111',
   'Image-less Recipe',
   '# No image yet');

delete from public.cookbook_recipes
 where id = 'aaaaaaaa-1111-2222-3333-444444444444';

select is(
  (select count(*)::int from public.cookbook_recipes
     where id = 'aaaaaaaa-1111-2222-3333-444444444444'),
  0,
  'cookbook_recipes row with NULL image_url deletes cleanly (no trigger error)'
);

select * from finish();

rollback;
