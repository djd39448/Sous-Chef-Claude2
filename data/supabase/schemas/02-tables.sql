-- 02-tables.sql — every public-schema table the app reads or writes.
--
-- Depends on:     00-extensions.sql (UUID source);
--                 01-app-private.sql (uuidv7() PK default);
--                 auth.users (Supabase Auth-managed; FK target).
-- Depended on by: 03-rls.sql (policies attach here);
--                 04-storage.sql (cookbook bucket references cookbook_recipes);
--                 05-triggers.sql (updated_at + cookbook-delete cascade
--                                  attach here).
-- Why it exists:  All eight tables live in one file so the relationships
--                 are read once, top to bottom, in the order a reader
--                 would draw them on paper:
--                   food_items (CFO — stand-alone, the data anchor)
--                   meal_plans → meal_plan_days
--                   cookbook_recipes (stand-alone)
--                   shopping_lists → shopping_list_items
--                   kitchen_conversations → kitchen_messages
--                 The contract (§4) is the source of truth for every column,
--                 constraint, and index in this file. Where the contract
--                 omits a unique-index or check name, the table file picks
--                 a descriptive snake_case name and the choice is captured
--                 in an inline comment.
--
-- Convention: every CHECK constraint is *named* (never anonymous) so
-- error messages from the wire surface a stable identifier the client
-- can branch on. Every JSONB sub-document column carries its expected
-- shape in a column comment; the wire honours those shapes (contract §7).

-- ============================================================================
-- §4.2  food_items — the Canonical Food Object (CFO).
-- One row backs an item across roles (inventory, shopping, planned,
-- ingredient). The (user_id, canonical_name, role) uniqueness invariant
-- ensures one shopping-row and one inventory-row per item per user.
-- ============================================================================

create table public.food_items (
  id              uuid not null default app_private.uuidv7(),
  user_id         uuid not null,
  canonical_name  text not null,
  display_name    text not null,
  quantity        jsonb,
  category        jsonb not null,
  attributes      jsonb not null default '{}'::jsonb,
  flexibility     jsonb not null default
                    '{"substitution_allowed": true,
                      "acceptable_variants": [],
                      "strict": false}'::jsonb,
  usage_context   jsonb not null,
  inventory_state jsonb not null default
                    '{"status": "unknown",
                      "on_hand_amount": null,
                      "last_confirmed": null}'::jsonb,
  sourcing        jsonb not null default
                    '{"store_affinity": null,
                      "bulk_allowed": true,
                      "generic_ok": true}'::jsonb,
  metadata        jsonb not null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint food_items_pkey primary key (id),
  constraint food_items_user_id_fkey
    foreign key (user_id) references auth.users (id) on delete cascade,

  -- canonical_name is the *normalised* identifier (lowercase, singular,
  -- generic). display_name carries the user-facing form. Storing both
  -- means lookups never need lower() and display preserves the AI's
  -- chosen capitalisation.
  constraint food_items_canonical_name_lowercase
    check (canonical_name = lower(canonical_name)),
  constraint food_items_canonical_name_nonempty
    check (length(canonical_name) > 0),

  -- category.primary is a closed 9-value set; secondary is open text.
  constraint food_items_category_primary_known
    check (category->>'primary' in
      ('produce','dairy','meat','seafood','pantry','frozen',
       'bakery','beverages','other')),

  -- usage_context.role admits all four CFO roles per ADR-0009. Only
  -- `inventory` and `shopping` are written by v1 code; the other two
  -- are reserved. The schema documents the design space.
  constraint food_items_usage_context_role_known
    check (usage_context->>'role' in
      ('inventory','shopping','planned','ingredient')),

  -- inventory_state.status is the source-of-truth for "do I have this?".
  -- `out` rows are kept (not deleted) so AI context can see prior items.
  constraint food_items_inventory_state_status_known
    check (inventory_state->>'status' in
      ('confirmed','likely','unknown','out')),

  -- metadata.created_by records whether the row was written by the AI
  -- tool path or by a future user-facing CRUD path.
  constraint food_items_metadata_created_by_known
    check (metadata->>'created_by' in ('ai','user'))
);

comment on table public.food_items is
  'CFO — one row per (user, canonical_name, role). Backs inventory, '
  'shopping, planned-ingredient and recipe-ingredient surfaces. '
  'See contract §4.2.';

comment on column public.food_items.canonical_name is
  'Normalised lookup key: lowercase, singular, generic (e.g. "milk").';
comment on column public.food_items.display_name is
  'Human-readable form for UI (e.g. "Whole Milk").';
comment on column public.food_items.quantity is
  'Optional { amount: number, unit: string }. Null when role is inventory '
  'and the AI only confirmed presence, not amount.';
comment on column public.food_items.category is
  '{ primary: enum, secondary?: string }. primary enumerates the 9 shop '
  'categories used by shopping_list_items.category.';
comment on column public.food_items.attributes is
  'Open key/value map for AI-discovered facets (e.g. organic, low-sodium). '
  'Schemaless by design — dc-04''s JSONB carve-out applies.';
comment on column public.food_items.flexibility is
  '{ substitution_allowed: bool, acceptable_variants: string[], strict: bool }. '
  'Drives whether the AI may swap items when generating a shopping list.';
comment on column public.food_items.usage_context is
  '{ role: enum, required?, recipe_ids?, meal_plan_id?, shopping_list_id? }. '
  'role distinguishes the four CFO surfaces; the optional foreign keys '
  'point back at the related plan/list. The food_items_user_canonical_role_uniq '
  'index makes role load-bearing.';
comment on column public.food_items.inventory_state is
  '{ status, on_hand_amount, last_confirmed }. status drives the chat-context '
  'filter (status != "out"); last_confirmed is updated on every AI confirmation.';
comment on column public.food_items.sourcing is
  '{ store_affinity, bulk_allowed, generic_ok }. Informs the shopping AI.';
comment on column public.food_items.metadata is
  '{ created_by: ai|user, confidence: 0..1 }. created_by is enforced by check.';

-- Uniqueness invariant (contract §4.2 + behavior spec §2.1):
-- one row per (user, canonical_name, role). Expression index because
-- the role is JSONB-stored.
create unique index food_items_user_canonical_role_uniq
  on public.food_items (user_id, canonical_name, (usage_context->>'role'));

-- RLS index target — every owner-scoped policy filters on user_id.
create index food_items_user_id_idx on public.food_items (user_id);


-- ============================================================================
-- §4.3  meal_plans / meal_plan_days — one plan per user-week, with day rows.
-- The week_start_is_monday CHECK is the database-side enforcement of
-- ADR-0010 (client-supplied Monday). If a backend bug ever sends a non-
-- Monday date through, the INSERT fails fast.
-- ============================================================================

create table public.meal_plans (
  id              uuid not null default app_private.uuidv7(),
  user_id         uuid not null,
  week_start_date date not null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint meal_plans_pkey primary key (id),
  constraint meal_plans_user_id_fkey
    foreign key (user_id) references auth.users (id) on delete cascade,

  -- ISO weekday: Monday = 1. extract(isodow ...) is timezone-agnostic
  -- (a `date` has no tz). Fails fast on a Tuesday input — see ADR-0010.
  constraint meal_plans_week_start_is_monday
    check (extract(isodow from week_start_date) = 1)
);

comment on table public.meal_plans is
  'One row per (user, week). week_start_date is the Monday in the user''s '
  'local week, supplied by the client (ADR-0010). See contract §4.3.';
comment on column public.meal_plans.week_start_date is
  'Calendar date with no timezone. Must be a Monday — the CHECK constraint '
  'meal_plans_week_start_is_monday enforces this.';

-- One plan per (user, week). Replaces "find by user+week" lookup.
create unique index meal_plans_user_week_uniq
  on public.meal_plans (user_id, week_start_date);

create index meal_plans_user_id_idx on public.meal_plans (user_id);


create table public.meal_plan_days (
  id                   uuid not null default app_private.uuidv7(),
  meal_plan_id         uuid not null,
  day_of_week          smallint not null,
  meal_name            text not null,
  notes                text,
  recipe_content       text,
  recipe_image_prompt  text,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),

  constraint meal_plan_days_pkey primary key (id),
  constraint meal_plan_days_meal_plan_id_fkey
    foreign key (meal_plan_id)
      references public.meal_plans (id) on delete cascade,

  -- JS-Sunday-first 0..6 per contract §3.3. UI ordering is a client
  -- concern; storage is wire-shape.
  constraint meal_plan_days_day_of_week_range
    check (day_of_week between 0 and 6),

  -- A day with an empty meal_name is meaningless; reject it.
  constraint meal_plan_days_meal_name_nonempty
    check (length(meal_name) > 0)
);

comment on table public.meal_plan_days is
  'One row per day in a meal plan. recipe_content and recipe_image_prompt '
  'are caches that are nulled by 05-triggers.sql when meal_name changes '
  '(cache-clearing invariant, contract §4.3).';
comment on column public.meal_plan_days.day_of_week is
  'JS Date.getDay() convention: 0=Sunday … 6=Saturday. UI re-orders to '
  'Monday-first; the wire and storage stay Sunday-first.';
comment on column public.meal_plan_days.recipe_content is
  'Markdown cache of the recipe body. Nullable — populated by '
  'POST /api/kitchen/meal-plan-days/{id}/generate-recipe; nulled by the '
  'cache-clearing trigger when meal_name changes.';
comment on column public.meal_plan_days.recipe_image_prompt is
  'Templated prompt for on-demand image generation. Same cache lifecycle '
  'as recipe_content.';

-- A meal plan has at most one day-row per day_of_week.
create unique index meal_plan_days_plan_day_uniq
  on public.meal_plan_days (meal_plan_id, day_of_week);

-- FK index — used by RLS policy (owns_meal_plan helper) and by cascade-
-- delete; without it every parent delete scans this whole table.
create index meal_plan_days_meal_plan_id_idx
  on public.meal_plan_days (meal_plan_id);


-- ============================================================================
-- §4.4  cookbook_recipes — user-saved recipes; image bytes live in the
-- cookbook-images Storage bucket. Per ADR-0004, there is no thumbnail_url
-- column; image_url is the single image pointer.
-- ============================================================================

create table public.cookbook_recipes (
  id           uuid not null default app_private.uuidv7(),
  user_id      uuid not null,
  title        text not null,
  content      text not null,
  image_prompt text,
  image_url    text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  constraint cookbook_recipes_pkey primary key (id),
  constraint cookbook_recipes_user_id_fkey
    foreign key (user_id) references auth.users (id) on delete cascade,

  -- Wire validates these too (empty_title / empty_content errors,
  -- contract §3.5) — the DB is the last line of defence.
  constraint cookbook_recipes_title_nonempty
    check (length(title) > 0),
  constraint cookbook_recipes_content_nonempty
    check (length(content) > 0)
);

comment on table public.cookbook_recipes is
  'User''s saved recipes. content is markdown in the canonical recipe '
  'format (see /sous-chef-ai/shared/schema.ts header comment). image_url '
  'points at the cookbook-images bucket; bytes are generated inline at '
  'save time per ADR-0004.';
comment on column public.cookbook_recipes.image_prompt is
  'The prompt used to generate image_url''s bytes. Stored so the regenerate-'
  'image endpoint (contract §5.6) can re-run image.Generate without a fresh '
  'AI round-trip.';
comment on column public.cookbook_recipes.image_url is
  'Supabase Storage public URL — cookbook-images/{user_id}/{id}.png. Null '
  'until the bytes land. The 05-triggers.sql cookbook-delete trigger '
  'removes the storage object when this row is deleted, so a delete is '
  'atomic with image cleanup (contract §5.6).';

create index cookbook_recipes_user_id_idx
  on public.cookbook_recipes (user_id);

-- Auto-save de-dup index (contract §9.8). The recipe-generation auto-save
-- path uses `lower(title) = lower(meal_name)` to skip duplicates.
create index cookbook_recipes_user_title_lower_idx
  on public.cookbook_recipes (user_id, lower(title));


-- ============================================================================
-- §4.5  shopping_lists / shopping_list_items — the check-off UI surface.
-- The week_start_date is nullable (free-form lists), but when populated
-- must be a Monday. The partial unique index enforces "one week-tied
-- list per (user, week)" without forbidding multiple free-form lists.
-- ============================================================================

create table public.shopping_lists (
  id              uuid not null default app_private.uuidv7(),
  user_id         uuid not null,
  name            text not null default 'Shopping List',
  week_start_date date,
  meal_plan_id    uuid,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint shopping_lists_pkey primary key (id),
  constraint shopping_lists_user_id_fkey
    foreign key (user_id) references auth.users (id) on delete cascade,
  -- If the linked meal plan is deleted, keep the list (it carries
  -- check-off state). Setting meal_plan_id null is the documented
  -- ON DELETE action per contract §4.5.
  constraint shopping_lists_meal_plan_id_fkey
    foreign key (meal_plan_id)
      references public.meal_plans (id) on delete set null,

  -- Free-form lists allow NULL; week-tied lists must anchor on a Monday.
  constraint shopping_lists_week_start_is_monday_or_null
    check (week_start_date is null
        or extract(isodow from week_start_date) = 1)
);

comment on table public.shopping_lists is
  'One row per shopping list. week_start_date links a list to a meal-plan '
  'week; if NULL the list is free-form (manual). See contract §4.5.';
comment on column public.shopping_lists.week_start_date is
  'Optional Monday-of-week anchor. NULL = free-form list.';
comment on column public.shopping_lists.meal_plan_id is
  'Optional link back to the meal plan that seeded the list. ON DELETE SET '
  'NULL preserves the list and its check-off state when the plan is dropped.';

-- One week-tied list per (user, week). Free-form lists (NULL week) are
-- unconstrained — the partial WHERE clause does the heavy lifting.
create unique index shopping_lists_user_week_uniq
  on public.shopping_lists (user_id, week_start_date)
  where week_start_date is not null;

create index shopping_lists_user_id_idx
  on public.shopping_lists (user_id);

-- meal_plan_id is RLS-joined indirectly through user_id; explicit index
-- so the ON DELETE SET NULL cascade is index-driven.
create index shopping_lists_meal_plan_id_idx
  on public.shopping_lists (meal_plan_id);


create table public.shopping_list_items (
  id               uuid not null default app_private.uuidv7(),
  shopping_list_id uuid not null,
  name             text not null,
  quantity         text,
  category         text not null,
  checked          boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  constraint shopping_list_items_pkey primary key (id),
  constraint shopping_list_items_shopping_list_id_fkey
    foreign key (shopping_list_id)
      references public.shopping_lists (id) on delete cascade,

  -- Same 9-value enum as food_items.category->>'primary'. Keeping the
  -- value enumerated inline (rather than via a lookup table) tracks the
  -- contract verbatim; the value rarely changes.
  constraint shopping_list_items_category_known
    check (category in
      ('produce','dairy','meat','seafood','pantry','frozen',
       'bakery','beverages','other')),
  constraint shopping_list_items_name_nonempty
    check (length(name) > 0)
);

comment on table public.shopping_list_items is
  'Check-off rows backing the shopping UI. Parallel-written with '
  'food_items (role = "shopping") by the create_shopping_list AI tool '
  '(dual-write behaviour preserved from the source pin, contract §4.5).';
comment on column public.shopping_list_items.quantity is
  'Free-form "{amount} {unit}" string. The structured quantity lives on '
  'the parallel food_items row; this column powers the UI.';
comment on column public.shopping_list_items.checked is
  'Boolean (the source pin stored 0|1 integer; ported to native boolean). '
  'Toggling this does NOT mutate the parallel food_items row.';

create index shopping_list_items_list_id_idx
  on public.shopping_list_items (shopping_list_id);


-- ============================================================================
-- §4.6  kitchen_conversations / kitchen_messages — the main-chat history.
-- kitchen_messages is APPEND-ONLY: 03-rls.sql declares only INSERT and
-- SELECT policies for it; UPDATE and DELETE attempts by an authenticated
-- caller fail with "row violates row-level security policy" (which is the
-- desired behaviour — append-only is enforced by policy absence).
-- ============================================================================

create table public.kitchen_conversations (
  id         uuid not null default app_private.uuidv7(),
  user_id    uuid not null,
  title      text not null default 'New Chat',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint kitchen_conversations_pkey primary key (id),
  constraint kitchen_conversations_user_id_fkey
    foreign key (user_id) references auth.users (id) on delete cascade
);

comment on table public.kitchen_conversations is
  'One row per persistent chat thread. Title is auto-set by the Go '
  'backend on first user message (contract §4.6). The recipe-page chat '
  'does NOT create rows here (ADR-0008 — stateless).';
comment on column public.kitchen_conversations.title is
  'Defaults to "New Chat". Backend overwrites on first user message with '
  'the first ~6 words / 40 chars of that message.';

-- Sidebar ordering: newest-updated first.
create index kitchen_conversations_user_updated_idx
  on public.kitchen_conversations (user_id, updated_at desc);


create table public.kitchen_messages (
  id              uuid not null default app_private.uuidv7(),
  conversation_id uuid not null,
  role            text not null,
  content         text not null,
  metadata        jsonb,
  created_at      timestamptz not null default now(),

  constraint kitchen_messages_pkey primary key (id),
  constraint kitchen_messages_conversation_id_fkey
    foreign key (conversation_id)
      references public.kitchen_conversations (id) on delete cascade,

  -- Only two roles in v1. Tool-call traces (if ever persisted) would be
  -- a future role and require a new migration.
  constraint kitchen_messages_role_known
    check (role in ('user','assistant')),
  constraint kitchen_messages_content_nonempty
    check (length(content) > 0)
);

comment on table public.kitchen_messages is
  'Append-only chat messages. No updated_at column — messages are '
  'immutable after insert. The append-only invariant is enforced by '
  '03-rls.sql declaring only INSERT and SELECT policies for the '
  'authenticated role; UPDATE / DELETE attempts fail RLS. The cascade '
  'from the parent conversation still works because FK cascade does not '
  'consult RLS policies.';
comment on column public.kitchen_messages.metadata is
  'Reserved for future use (tool-call provenance, token counts, etc.). '
  'Null on every v1 insert.';

-- Replay order within a conversation.
create index kitchen_messages_conversation_created_idx
  on public.kitchen_messages (conversation_id, created_at);
