-- 04-storage.sql — the cookbook-images Storage bucket + storage.objects RLS.
--
-- Depends on:     Supabase's storage schema (bundled with `supabase start`
--                 and every cloud project — storage.buckets and
--                 storage.objects pre-exist).
-- Depended on by: 05-triggers.sql (the cookbook-delete trigger issues a
--                 `delete from storage.objects` against this bucket).
--                 The Go backend's image upload path (cookbook saves +
--                 regenerate) targets this bucket via the Storage REST API
--                 — wire details in contract §5.6 and ADR-0004.
-- Why it exists:  Per ADR-0004, cookbook images are persisted (not
--                 regenerated on view). The bucket has to exist before
--                 any save can land bytes, and storage.objects has its
--                 own RLS policies that must be authored deliberately.
--
-- Bucket parameters (ADR-0004 + contract §4.4):
--   * Name:           cookbook-images
--   * Private:        true (RLS-gated; no public URL listing)
--   * Size cap:       8 MB per object (file_size_limit)
--   * MIME:           image/png only (allowed_mime_types)
--   * Object key:     {user_id}/{cookbook_recipe_id}.png — the leading
--                     path segment is the user_id; the per-user RLS
--                     policies compare it to auth.uid()::text.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'cookbook-images',
  'cookbook-images',
  false,
  8388608,                    -- 8 MiB
  array['image/png']::text[]
)
on conflict (id) do update set
  public             = excluded.public,
  file_size_limit    = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- ============================================================================
-- storage.objects RLS — one policy per operation, scoped to this bucket,
-- gating access by the leading path segment matching auth.uid().
--
-- storage.objects already has RLS enabled by Supabase. We add bucket-
-- scoped policies; other buckets are untouched.
--
-- The `(storage.foldername(name))[1] = (select auth.uid())::text` form
-- is the documented Supabase pattern. storage.foldername() splits the
-- object's key on '/' and returns the array of segments; [1] is the
-- first segment, which by convention is the user_id.
-- ============================================================================

create policy cookbook_images_select_own on storage.objects
  for select to authenticated
  using (
    bucket_id = 'cookbook-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
comment on policy cookbook_images_select_own on storage.objects is
  'Caller reads only objects under cookbook-images/{their user_id}/.';

create policy cookbook_images_insert_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'cookbook-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
comment on policy cookbook_images_insert_own on storage.objects is
  'Caller uploads only into cookbook-images/{their user_id}/. The Go '
  'backend computes the object key as {user_id}/{recipe_id}.png — this '
  'policy enforces the user_id prefix can''t be forged.';

create policy cookbook_images_update_own on storage.objects
  for update to authenticated
  using (
    bucket_id = 'cookbook-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'cookbook-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
comment on policy cookbook_images_update_own on storage.objects is
  'The regenerate-image flow (contract §5.6) overwrites the existing '
  'object via Storage UPDATE — this policy permits it for the owner only.';

create policy cookbook_images_delete_own on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'cookbook-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
comment on policy cookbook_images_delete_own on storage.objects is
  'Manual delete path. The trigger in 05-triggers.sql runs as the table '
  'owner (no RLS check on a trigger-internal DELETE), so this policy '
  'covers a hypothetical Go-side direct-delete; the trigger remains the '
  'primary lifecycle hook.';
