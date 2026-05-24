# Dockerfile — multi-stage build for the sous-chef-api binary.
#
# Depends on: an OCI builder (Docker, Buildx, or podman) and network access
# to fetch the golang and distroless base images.
# Depended on by: the ECS Fargate task definition (deploy is Phase L; the
# image lands in ECR before the task runs).
# Why it exists: production runs the binary in a tiny container. A
# multi-stage build keeps the final image at ~20 MB (binary only — no
# toolchain, no shell, no package manager) and the attack surface flat.

# ─── Stage 1: build ───────────────────────────────────────────────────
# pin the build image to a recent Go 1.26 minor version. Bumping it is a
# deliberate one-line change reviewed in PR; we never `golang:latest` in
# production.
FROM golang:1.26.3-alpine AS builder

WORKDIR /src

# Copy go.mod and go.sum first so a code-only change does not invalidate
# the (slow) dependency-download layer.
COPY go.mod go.sum* ./
RUN go mod download

# Now pull the rest of the source. .dockerignore filters out test caches,
# bin/, and anything else that would balloon the build context.
COPY . .

# Build stripped, statically-linked, with a fixed VERSION/BUILD_TIME that
# the build environment provides. CGO_ENABLED=0 plus the netgo tag yields a
# binary that runs in a scratch container without a libc.
ARG VERSION=docker
ARG BUILD_TIME=unknown
ENV CGO_ENABLED=0

RUN go build \
      -tags netgo \
      -ldflags "-s -w \
        -X github.com/djd39448/Sous-Chef-Claude2/backend/internal/buildinfo.Version=${VERSION} \
        -X github.com/djd39448/Sous-Chef-Claude2/backend/internal/buildinfo.BuildTime=${BUILD_TIME}" \
      -o /out/sous-chef-api ./cmd/sous-chef-api

# ─── Stage 2: runtime ─────────────────────────────────────────────────
# distroless/static carries CA roots and timezone data — enough to call
# Supabase and OpenAI over HTTPS without bundling a shell or libc. The
# :nonroot tag runs the entrypoint as uid 65532 by default.
FROM gcr.io/distroless/static-debian12:nonroot

WORKDIR /app
COPY --from=builder /out/sous-chef-api /app/sous-chef-api

# The default listener is :8080 (config.defaultPort); ECS task definitions
# can override via PORT.
EXPOSE 8080

ENTRYPOINT ["/app/sous-chef-api"]
