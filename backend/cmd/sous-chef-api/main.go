// Command sous-chef-api is the HTTP service that backs the Sous Chef Claude2
// iOS app. It implements the shared contract — the four AI tool calls, the
// SSE chat stream, the REST endpoints under /api/kitchen/*, image generation,
// and the cookbook flow — talking to Supabase for persistence and to OpenAI
// for the AI surface.
//
// Depends on: internal/config (env-driven boot configuration),
// internal/server (the HTTP plumbing — middleware chain, /healthz, the
// route mux), log/slog (structured JSON logging at the root).
// Depended on by: nothing in Go — this is a process entrypoint. In
// production the binary runs as an ECS Fargate task fronted by an ALB.
// Why it exists: every binary needs a `main`. Keeping it small — config,
// logger, server, signal handling — makes the boot sequence obvious. All
// real work lives in internal/.
//
// Usage:
//
//	sous-chef-api          # binds 127.0.0.1:$PORT (default 8080)
//	sous-chef-api --help   # not implemented; envvars are the only knobs
//
// Configuration is exclusively via environment variables — see internal/
// config for the full set. Required secrets must be present or the binary
// exits 1 before opening a listener.
package main

import (
	"context"
	"fmt"
	"log/slog"
	"net"
	"os"
	"os/signal"
	"syscall"

	"github.com/djd39448/Sous-Chef-Claude2/backend/internal/config"
	"github.com/djd39448/Sous-Chef-Claude2/backend/internal/server"
)

func main() {
	if err := run(); err != nil {
		// slog isn't constructed yet if config.Load failed, so write the
		// last-line error directly to stderr — one structured line in JSON
		// so log aggregators still pick it up.
		fmt.Fprintf(os.Stderr, `{"level":"error","msg":"sous-chef-api boot failed","err":%q}`+"\n", err.Error())
		os.Exit(1)
	}
}

// run wires the binary together: load config → build logger → construct
// server → open listener → serve until signal. It returns an error rather
// than exiting so tests can drive it in-process and main stays trivial.
func run() error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("loading config: %w", err)
	}

	logger := newLogger(cfg.LogLevel)
	logger.Info(
		"sous-chef-api starting",
		slog.Int("port", cfg.Port),
		slog.String("log_level", cfg.LogLevel),
		slog.String("aws_region", cfg.AWSRegion),
	)

	srv, err := server.New(logger)
	if err != nil {
		return fmt.Errorf("constructing server: %w", err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	addr := fmt.Sprintf(":%d", cfg.Port)
	var lc net.ListenConfig
	ln, err := lc.Listen(ctx, "tcp", addr)
	if err != nil {
		return fmt.Errorf("binding %s: %w", addr, err)
	}
	logger.Info("listening", slog.String("addr", ln.Addr().String()))

	if err := srv.Serve(ctx, ln); err != nil {
		return fmt.Errorf("serving: %w", err)
	}
	logger.Info("sous-chef-api stopped")
	return nil
}

// newLogger returns the root structured JSON logger. JSON is the production
// shape (ECS task logs flow to CloudWatch, which indexes JSON). A developer
// who wants text output runs the binary through `jq -r` or sets
// LOG_LEVEL=debug and reads the JSON directly — there is no "developer
// mode" toggle on the format, only on the verbosity.
func newLogger(levelName string) *slog.Logger {
	var level slog.Level
	switch levelName {
	case "debug":
		level = slog.LevelDebug
	case "warn":
		level = slog.LevelWarn
	case "error":
		level = slog.LevelError
	default:
		// config.Load has already validated the level string, so reaching
		// this default means "info" — the documented default.
		level = slog.LevelInfo
	}
	handler := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: level})
	return slog.New(handler)
}
