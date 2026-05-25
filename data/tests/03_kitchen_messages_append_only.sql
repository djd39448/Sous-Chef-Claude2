-- 03_kitchen_messages_append_only.sql — kitchen_messages is append-only
-- for the authenticated role: INSERT and SELECT only, no UPDATE / DELETE.
--
-- Depends on:     pgTAP extension (`create extension pgtap`);
--                 supabase/schemas/* applied (via `supabase db reset`).
-- Depended on by: CI's `make test` target. The track-data §5 task 18
--                 acceptance check requires (c) kitchen_messages
--                 append-only enforcement; this file is that proof.
-- Why it exists:  03-rls.sql declares only INSERT and SELECT policies on
--                 kitchen_messages. Append-only is enforced by *policy
--                 absence*: under RLS default-deny, an UPDATE or DELETE
--                 by the authenticated role matches no policy and is
--                 rejected. This is the only check in the suite that
--                 exercises the "policy absence = denial" pattern. A
--                 future refactor that accidentally lands an UPDATE or
--                 DELETE policy on kitchen_messages would silently break
--                 the contract §4.6 immutability invariant — this test
--                 fails loud in that case.
--
-- Test strategy: insert a user + a conversation + a message (as superuser).
-- Then under the authenticated role, assert the owner CAN read and CAN
-- insert; assert the owner CANNOT UPDATE or DELETE; assert FK cascade
-- delete from the parent conversation still removes the message (cascade
-- bypasses RLS — track-data §8 R8).

begin;

select plan(7);

-- ----------------------------------------------------------------------------
-- Fixture.
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

insert into public.kitchen_conversations (id, user_id, title)
values
  ('cccccccc-cccc-cccc-cccc-cccccccccccc',
   '11111111-1111-1111-1111-111111111111',
   'Test Conversation');

insert into public.kitchen_messages (id, conversation_id, role, content)
values
  ('dddddddd-dddd-dddd-dddd-dddddddddddd',
   'cccccccc-cccc-cccc-cccc-cccccccccccc',
   'user',
   'Original immutable message body');

-- ----------------------------------------------------------------------------
-- Impersonate user A — the conversation owner. Append-only invariants
-- must hold even for the owner.
-- ----------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

-- 1. Owner CAN SELECT their own message (positive control: the SELECT
-- policy is wired and reads correctly).
select is(
  (select content from public.kitchen_messages
     where id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'),
  'Original immutable message body',
  'owner can SELECT their own kitchen_messages row (positive control)'
);

-- 2. Owner CAN INSERT a new message into their own conversation
-- (positive control on the INSERT policy).
insert into public.kitchen_messages (conversation_id, role, content)
values ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'assistant', 'Reply body');

select is(
  (select count(*)::int from public.kitchen_messages
     where conversation_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
  2,
  'owner can INSERT a new kitchen_messages row (positive control)'
);

-- 3. Owner CANNOT UPDATE their own message — no UPDATE policy is
-- declared for the authenticated role, so RLS default-deny fires. The
-- UPDATE matches zero rows (USING-clause-style filter; the policy
-- system treats "no policy" as "no row qualifies").
update public.kitchen_messages
   set content = 'Tampered body'
 where id = 'dddddddd-dddd-dddd-dddd-dddddddddddd';

select is(
  (select content from public.kitchen_messages
     where id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'),
  'Original immutable message body',
  'owner UPDATE against kitchen_messages is silently no-op (policy absence)'
);

-- 4. Owner CANNOT DELETE their own message — same reasoning as (3).
delete from public.kitchen_messages
 where id = 'dddddddd-dddd-dddd-dddd-dddddddddddd';

select is(
  (select count(*)::int from public.kitchen_messages
     where id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'),
  1,
  'owner DELETE against kitchen_messages is silently no-op (policy absence)'
);

-- 5. Inspect pg_policies directly: there is no UPDATE policy on
-- kitchen_messages for the authenticated role. This is structural — a
-- future contributor adding such a policy would flip this assertion.
select is(
  (select count(*)::int from pg_policies
     where schemaname = 'public'
       and tablename = 'kitchen_messages'
       and cmd = 'UPDATE'),
  0,
  'no UPDATE policy is declared on public.kitchen_messages'
);

-- 6. Same structural check for DELETE.
select is(
  (select count(*)::int from pg_policies
     where schemaname = 'public'
       and tablename = 'kitchen_messages'
       and cmd = 'DELETE'),
  0,
  'no DELETE policy is declared on public.kitchen_messages'
);

-- ----------------------------------------------------------------------------
-- Cascade-delete from the parent conversation still works — FK cascade
-- runs at the constraint layer, which does not consult RLS policies.
-- track-data §8 R8 calls this out; we assert it directly here so a
-- future "fix" that swaps cascade for trigger-based delete cannot break
-- it silently.
-- ----------------------------------------------------------------------------

set local role postgres;
reset request.jwt.claim.sub;

-- Confirm setup: two messages currently under the conversation.
select is(
  (select count(*)::int from public.kitchen_messages
     where conversation_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
  2,
  'pre-cascade: 2 messages under the conversation (the original + the reply)'
);

-- Delete the parent conversation. FK on kitchen_messages.conversation_id
-- is ON DELETE CASCADE; the children must go with it.
delete from public.kitchen_conversations
 where id = 'cccccccc-cccc-cccc-cccc-cccccccccccc';

-- 7. After cascade, zero messages remain under that conversation_id.
select is(
  (select count(*)::int from public.kitchen_messages
     where conversation_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
  0,
  'FK ON DELETE CASCADE removed messages even though no DELETE RLS policy exists'
);

select * from finish();

rollback;
