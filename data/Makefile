# Makefile — local Supabase stack management for the data track.
#
# Depends on:     supabase CLI >= 1.200 (brew install supabase/tap/supabase);
#                 docker (engine 24+, required by `supabase start`).
# Depended on by: every Builder who needs a local Supabase stack — the
#                 backend track (Go integration tests) and the iOS track
#                 (preview-time RLS smoke checks) both `cd data/ && make up`.
# Why it exists:  dc-04 mandates "Develop against the local stack". The
#                 Makefile makes the workflow one-command and consistent
#                 across developers without anyone memorising CLI flags.
#
# Targets:
#   make up        — start the local Supabase stack (Docker required).
#   make down      — stop the local Supabase stack.
#   make reset     — drop and rebuild the local DB from schemas/ + seed.sql.
#   make diff name=<descriptive_name>
#                  — generate a migration file capturing changes since the
#                    last applied migration. The name lands in
#                    supabase/migrations/<timestamp>_<name>.sql.
#   make test      — run the pgTAP suite under tests/. Requires pgTAP to be
#                    installed locally; skipped with a notice if not.
#   make doctor    — print what's installed (supabase, docker, pg_prove)
#                    and exit. Useful when a teammate's `make up` fails.
#
# All targets are phony — nothing here builds a file artefact.

.PHONY: up down reset diff test doctor

SUPABASE := $(shell command -v supabase 2>/dev/null)
DOCKER   := $(shell command -v docker 2>/dev/null)
PG_PROVE := $(shell command -v pg_prove 2>/dev/null)

# Local DB connection string — supabase start exposes Postgres on 54322
# with the default superuser. The Makefile uses this only for `test`
# (running pgTAP through pg_prove). The Go and iOS tracks read their own
# connection strings from .env files, not from here.
LOCAL_DB_URL ?= postgresql://postgres:postgres@127.0.0.1:54322/postgres

up:
	@if [ -z "$(SUPABASE)" ]; then \
	  echo "supabase CLI not installed. brew install supabase/tap/supabase"; \
	  exit 1; \
	fi
	@if [ -z "$(DOCKER)" ]; then \
	  echo "docker not installed. supabase start needs Docker."; \
	  exit 1; \
	fi
	supabase start

down:
	@if [ -z "$(SUPABASE)" ]; then \
	  echo "supabase CLI not installed."; \
	  exit 1; \
	fi
	supabase stop

reset:
	@if [ -z "$(SUPABASE)" ]; then \
	  echo "supabase CLI not installed."; \
	  exit 1; \
	fi
	supabase db reset

# `name` must be supplied: `make diff name=add_food_items_email_index`.
# A bare `make diff` errors out so we don't accidentally emit a migration
# named "diff" or similar.
diff:
	@if [ -z "$(name)" ]; then \
	  echo "usage: make diff name=<descriptive_snake_case_name>"; \
	  exit 2; \
	fi
	@if [ -z "$(SUPABASE)" ]; then \
	  echo "supabase CLI not installed."; \
	  exit 1; \
	fi
	supabase db diff -f $(name)

test:
	@if [ -z "$(PG_PROVE)" ]; then \
	  echo "pg_prove not installed — skipping pgTAP tests."; \
	  echo "Install with: cpan TAP::Parser::SourceHandler::pgTAP"; \
	  echo "(and the pgtap extension on the running Postgres)."; \
	  exit 0; \
	fi
	pg_prove --ext .sql --recurse tests/ \
	  --dbname=postgres --host=127.0.0.1 --port=54322 --username=postgres

doctor:
	@echo "supabase: $(if $(SUPABASE),$(SUPABASE),NOT INSTALLED)"
	@echo "docker:   $(if $(DOCKER),$(DOCKER),NOT INSTALLED)"
	@echo "pg_prove: $(if $(PG_PROVE),$(PG_PROVE),NOT INSTALLED)"
	@echo "LOCAL_DB_URL: $(LOCAL_DB_URL)"
