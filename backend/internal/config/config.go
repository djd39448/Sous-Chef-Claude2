// Package config loads, validates, and exposes the runtime configuration the
// sous-chef-api binary needs to boot. Configuration comes exclusively from
// environment variables (twelve-factor; dc-05) and is read once at startup;
// the resulting Config is immutable and passed down the dependency tree.
//
// Depends on: standard library only. Reading secrets from AWS Secrets Manager
// at boot is a Phase L concern; the current implementation treats every
// secret-valued env var as a literal value, which is correct for local
// development and for an ECS task whose secrets are injected by the task
// definition's `secrets:` block.
// Depended on by: cmd/sous-chef-api (calls Load at boot, fatals on error),
// and — via dependency injection — every package that needs a value
// (internal/auth, internal/store, internal/aiclient).
// Why it exists: scattering os.Getenv calls across the codebase hides the
// boot contract. One typed Config in one place means a new developer can
// answer "what does this service need to run?" by reading one file.
package config

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
)

// Defaults captured here so the field documentation and the Load logic stay
// in one place. dc-02: named constants over magic numbers/strings.
const (
	defaultPort             = 8080
	defaultLogLevel         = "info"
	defaultChatModel        = "gpt-4.1"
	defaultImageModel       = "gpt-image-1"
	defaultStorageBucket    = "cookbook-images"
	defaultHeartbeatSeconds = 20
)

// Config is the validated, typed snapshot of every value the service reads
// from the environment at boot. Field names mirror the plan §3.4 env-var
// names so the mapping stays obvious without a translation table.
type Config struct {
	// Port is the TCP port the HTTP server binds. Default 8080.
	Port int

	// LogLevel is the slog level — one of "debug", "info", "warn", "error".
	// Default "info".
	LogLevel string

	// SupabaseJWKSURL is the JWKS endpoint the auth middleware fetches keys
	// from. Required. Example:
	// https://<project>.supabase.co/auth/v1/.well-known/jwks.json
	SupabaseJWKSURL string

	// SupabaseIssuer is the expected `iss` claim on every JWT. Required.
	// Example: https://<project>.supabase.co/auth/v1
	SupabaseIssuer string

	// SupabaseDBURL is the Postgres DSN the store package connects with.
	// Required, secret. Per ADR-0011 this connects as the `authenticated`
	// role, never service-role.
	SupabaseDBURL string

	// SupabaseStorageURL is the base URL of the Supabase Storage REST API.
	// Required. Example: https://<project>.supabase.co/storage/v1
	SupabaseStorageURL string

	// SupabaseServiceRoleKey is the secret used to upload to Supabase
	// Storage on behalf of any user. Required, secret. Per ADR-0011 it is
	// not used for database access — Storage REST is the sole consumer.
	SupabaseServiceRoleKey string

	// OpenAIAPIKey is the OpenAI bearer credential. Required, secret.
	OpenAIAPIKey string

	// OpenAIChatModel is the OpenAI model id for chat-completions calls.
	// Default "gpt-4.1". Override in staging to test newer snapshots.
	OpenAIChatModel string

	// OpenAIImageModel is the OpenAI model id for image generation.
	// Default "gpt-image-1".
	OpenAIImageModel string

	// StorageBucketCookbook is the Supabase Storage bucket name for
	// cookbook recipe images. Default "cookbook-images".
	StorageBucketCookbook string

	// AWSRegion is the AWS region the deployment runs in. Required in
	// production for log routing and secret hydration; not required for a
	// local developer run.
	AWSRegion string

	// SSEHeartbeatSeconds is the heartbeat cadence for SSE responses. Per
	// plan §8 R4 the default is 20s so ALB's idle timeout does not drop a
	// quiet stream.
	SSEHeartbeatSeconds int
}

// requireProduction is true unless explicitly disabled. Setting
// SOUS_CHEF_ENV=development relaxes the "production-only" requirements (the
// AWS region check) so a developer can boot the service from a laptop.
// Required secrets are still required in development — the service simply
// cannot run without them.
const developmentEnvName = "development"

// Load reads every supported environment variable, fills defaults, validates
// required values, and returns a Config. The first missing or malformed
// value aborts with an error that names the offending variable; the caller
// is expected to fatal-exit. Aggregating with errors.Join would let a
// developer see every problem at once, but most boots have at most one
// missing var and a single message is easier to read in CI logs.
func Load() (Config, error) {
	cfg := Config{
		Port:                  defaultPort,
		LogLevel:              defaultLogLevel,
		OpenAIChatModel:       defaultChatModel,
		OpenAIImageModel:      defaultImageModel,
		StorageBucketCookbook: defaultStorageBucket,
		SSEHeartbeatSeconds:   defaultHeartbeatSeconds,
	}

	if raw := os.Getenv("PORT"); raw != "" {
		port, err := strconv.Atoi(raw)
		if err != nil {
			return Config{}, fmt.Errorf("PORT %q is not an integer: %w", raw, err)
		}
		if port <= 0 || port > 65535 {
			return Config{}, fmt.Errorf("PORT %d out of range 1..65535", port)
		}
		cfg.Port = port
	}

	if raw := os.Getenv("LOG_LEVEL"); raw != "" {
		level := strings.ToLower(raw)
		if !isKnownLogLevel(level) {
			return Config{}, fmt.Errorf("LOG_LEVEL %q not one of debug|info|warn|error", raw)
		}
		cfg.LogLevel = level
	}

	if raw := os.Getenv("SSE_HEARTBEAT_SECONDS"); raw != "" {
		seconds, err := strconv.Atoi(raw)
		if err != nil {
			return Config{}, fmt.Errorf("SSE_HEARTBEAT_SECONDS %q is not an integer: %w", raw, err)
		}
		if seconds <= 0 {
			return Config{}, fmt.Errorf("SSE_HEARTBEAT_SECONDS %d must be positive", seconds)
		}
		cfg.SSEHeartbeatSeconds = seconds
	}

	required := []struct {
		name  string
		field *string
	}{
		{"SUPABASE_JWKS_URL", &cfg.SupabaseJWKSURL},
		{"SUPABASE_ISSUER", &cfg.SupabaseIssuer},
		{"SUPABASE_DB_URL", &cfg.SupabaseDBURL},
		{"SUPABASE_STORAGE_URL", &cfg.SupabaseStorageURL},
		{"SUPABASE_SERVICE_ROLE_KEY", &cfg.SupabaseServiceRoleKey},
		{"OPENAI_API_KEY", &cfg.OpenAIAPIKey},
	}
	for _, r := range required {
		v := os.Getenv(r.name)
		if v == "" {
			return Config{}, fmt.Errorf("required env var %s is unset or empty", r.name)
		}
		*r.field = v
	}

	if raw := os.Getenv("OPENAI_CHAT_MODEL"); raw != "" {
		cfg.OpenAIChatModel = raw
	}
	if raw := os.Getenv("OPENAI_IMAGE_MODEL"); raw != "" {
		cfg.OpenAIImageModel = raw
	}
	if raw := os.Getenv("STORAGE_BUCKET_COOKBOOK"); raw != "" {
		cfg.StorageBucketCookbook = raw
	}

	cfg.AWSRegion = os.Getenv("AWS_REGION")
	if cfg.AWSRegion == "" && os.Getenv("SOUS_CHEF_ENV") != developmentEnvName {
		return Config{}, errors.New(
			"required env var AWS_REGION is unset; set SOUS_CHEF_ENV=development to bypass on a developer machine",
		)
	}

	return cfg, nil
}

// isKnownLogLevel restricts LOG_LEVEL to the slog levels we explicitly map.
// Returning a typed slog.Level is the caller's job — config exposes a string
// to keep the package free of a slog import on the value path.
func isKnownLogLevel(level string) bool {
	switch level {
	case "debug", "info", "warn", "error":
		return true
	default:
		return false
	}
}
