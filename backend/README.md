# `backend/` — Go service on AWS

Implements the shared contract for Sous Chef Claude2. The iOS app talks to
this service; this service talks to Supabase and to OpenAI.

## Stack

- **Language:** Go 1.26 (`gofumpt`-clean, `golangci-lint`-clean).
- **Deploy target:** ECS Fargate. Lambda + API Gateway breaks SSE — chosen
  out for a steady-traffic API per ADR-0002 and the track plan §3.
- **Database access:** `pgxpool` against Supabase Postgres as the
  `authenticated` role; `SET LOCAL request.jwt.claim.sub` per request so
  RLS enforces per-user filtering (ADR-0011).
- **AI:** Direct OpenAI behind an `AIClient` interface (ADR-0002).
- **Streaming:** stdlib SSE via `http.Flusher` + a 20s heartbeat goroutine.

## Track plan (authoritative)

[`plan/track-backend.md`](https://github.com/djd39448/DevCore/blob/main/.devcore/memory/plan/track-backend.md)
— 41 tasks across 12 phases (foundation → auth → reads → AI → SSE → cookbook
→ shopping → deploy). Read it before opening any code.

## Contract

[`contract/contract.md`](https://github.com/djd39448/DevCore/blob/main/.devcore/memory/contract/contract.md)
is **the** spec. The whole `/api/kitchen/*` surface, the SSE wire format,
the four AI tool calls, the image-generation rules — all there.

## Layout (planned, populated in Phase 4)

```
backend/
  cmd/
    sous-chef-api/        ← main package
  internal/
    api/                  ← HTTP handlers (one per resource group)
    aiclient/             ← OpenAI interface + impl
    auth/                 ← Supabase JWT middleware (JWKS verification)
    store/                ← data access; SET LOCAL claims; pgxpool
    sse/                  ← small Writer + heartbeat helper
  Dockerfile
  Makefile
```

## Standards

[`CODING_STANDARDS.md`](https://github.com/djd39448/DevCore/blob/main/CODING_STANDARDS.md)
`dc-02` (Go) governs every file; `dc-05` (AWS) governs the deploy.
