# Sous Chef Claude2

Native iOS port of [Sous Chef AI](https://github.com/djd39448/sous-chef-ai),
re-platformed to the team's target stack. Built by
[DevCore](https://github.com/djd39448/DevCore) — the multi-agent dev harness.

This repo holds the **output** of DevCore's first workload (the sous-chef-ios
port). DevCore itself holds the **plans, contract, and decisions** that drove
it.

---

## What this is

The web app at `djd39448/sous-chef-ai` is a Replit-built React/Express/
Postgres kitchen assistant. This repo is its **native iOS re-platform**:

| Layer | From (web) | To (this repo) |
|-------|-----------|----------------|
| Database | Postgres + Drizzle ORM | **Supabase** — `data/` |
| Backend | Express/Node + TS | **Go on AWS** — `backend/` |
| Frontend | React + Vite + shadcn/ui | **SwiftUI** (iOS 17+) — `ios/` |
| Auth | Replit Auth via OIDC | **Sign in with Apple + Supabase email/OTP** |
| AI | OpenAI via Replit proxy | **Direct OpenAI** |
| Streaming | SSE | SSE over `URLSession.bytes` |

The port preserves the product (the Canonical Food Object data model, the
AI tool-calling contract, the feature set documented in the source's
`replit.md`). Every other layer is rebuilt natively.

## How to read this repo

Three top-level directories, each independently buildable against a single
shared contract:

- **`backend/`** — Go service implementing the shared contract. ECS Fargate.
  Stdlib SSE. Tracks plan: [`track-backend.md`](https://github.com/djd39448/DevCore/blob/main/.devcore/memory/plan/track-backend.md).
- **`data/`** — Supabase schemas, migrations, RLS policies, storage bucket
  and triggers. Declarative-state via the Supabase CLI. Track plan:
  [`track-data.md`](https://github.com/djd39448/DevCore/blob/main/.devcore/memory/plan/track-data.md).
- **`ios/`** — SwiftUI app. iOS 17, Swift 6, hybrid Xcode app target +
  in-repo `SousChefKit` Swift Package. Track plan:
  [`track-ios.md`](https://github.com/djd39448/DevCore/blob/main/.devcore/memory/plan/track-ios.md).

Each track's `README.md` repeats the essentials and points back to the
canonical plan in DevCore.

## Where the spec lives

The contract and decisions are version-controlled in the DevCore repo, not
duplicated here:

- **Behavior spec** (the product's behavior, scrubbed of platform mechanism):
  [`domain/sous-chef-behaviors.md`](https://github.com/djd39448/DevCore/blob/main/.devcore/memory/domain/sous-chef-behaviors.md)
- **Shared contract** (API surface + data model both backend and iOS bind to):
  [`contract/contract.md`](https://github.com/djd39448/DevCore/blob/main/.devcore/memory/contract/contract.md)
- **ADRs 0001–0011** (every significant decision and why):
  [`decisions/`](https://github.com/djd39448/DevCore/tree/main/.devcore/memory/decisions)
- **Cross-track integration synthesis**:
  [`plan/integration.md`](https://github.com/djd39448/DevCore/blob/main/.devcore/memory/plan/integration.md)

If the contract changes, it changes in DevCore first, then propagates here.
This repo never edits the contract directly.

## Status

**Phase 3 (planning) complete in DevCore.** Phase 4 (implementation) begins
when the first commit lands in `backend/`, `data/`, or `ios/`. As of the
initial commit, all three directories are placeholders.

## Standards

The DevCore coding standard binds every line in this repo:
[`CODING_STANDARDS.md`](https://github.com/djd39448/DevCore/blob/main/CODING_STANDARDS.md).
The `dc-00` bar applies — any developer handed this repo, with no
explanation, understands what it is and how to change it.

## License

TBD. The source web app at `djd39448/sous-chef-ai` carries no license file
at the source pin (`d884efa…`); this repo will pick one before it ships.
