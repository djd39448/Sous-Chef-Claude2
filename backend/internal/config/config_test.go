// Tests for the config loader. Each subtest sets a specific environment
// shape and asserts the typed Config it produces; the package under test is
// imported as "config_test" (black-box) per dc-02 to exercise only the
// exported API.

package config_test

import (
	"strings"
	"testing"

	"github.com/djd39448/Sous-Chef-Claude2/backend/internal/config"
)

// requiredEnv is the set of env vars Load demands. A test that wants a
// successful Load sets every one to a non-empty placeholder so the missing-
// var path is not what's under test.
var requiredEnv = map[string]string{
	"SUPABASE_JWKS_URL":         "https://example.supabase.co/auth/v1/.well-known/jwks.json",
	"SUPABASE_ISSUER":           "https://example.supabase.co/auth/v1",
	"SUPABASE_DB_URL":           "postgres://user:pass@localhost:5432/db",
	"SUPABASE_STORAGE_URL":      "https://example.supabase.co/storage/v1",
	"SUPABASE_SERVICE_ROLE_KEY": "test-service-role-key",
	"OPENAI_API_KEY":            "sk-test",
	"AWS_REGION":                "us-east-1",
}

// setEnv applies env (and only env) for the duration of the test, restoring
// the previous values on cleanup. t.Setenv handles process-wide isolation by
// disallowing t.Parallel — these tests intentionally do not opt into
// parallelism because they each rewrite the process environment.
func setEnv(t *testing.T, env map[string]string) {
	t.Helper()
	for k, v := range env {
		t.Setenv(k, v)
	}
}

func TestLoad_AllRequiredPresent_FillsDefaults(t *testing.T) {
	setEnv(t, requiredEnv)

	cfg, err := config.Load()
	if err != nil {
		t.Fatalf("Load() unexpected error: %v", err)
	}

	if cfg.Port != 8080 {
		t.Errorf("Port default: got %d, want 8080", cfg.Port)
	}
	if cfg.LogLevel != "info" {
		t.Errorf("LogLevel default: got %q, want %q", cfg.LogLevel, "info")
	}
	if cfg.OpenAIChatModel != "gpt-4.1" {
		t.Errorf("OpenAIChatModel default: got %q, want %q", cfg.OpenAIChatModel, "gpt-4.1")
	}
	if cfg.OpenAIImageModel != "gpt-image-1" {
		t.Errorf("OpenAIImageModel default: got %q, want %q", cfg.OpenAIImageModel, "gpt-image-1")
	}
	if cfg.StorageBucketCookbook != "cookbook-images" {
		t.Errorf("StorageBucketCookbook default: got %q, want %q", cfg.StorageBucketCookbook, "cookbook-images")
	}
	if cfg.SSEHeartbeatSeconds != 20 {
		t.Errorf("SSEHeartbeatSeconds default: got %d, want 20", cfg.SSEHeartbeatSeconds)
	}
}

func TestLoad_OverridesApplied(t *testing.T) {
	env := map[string]string{
		"PORT":                    "9090",
		"LOG_LEVEL":               "debug",
		"OPENAI_CHAT_MODEL":       "gpt-4.1-2024-04-09",
		"OPENAI_IMAGE_MODEL":      "dall-e-3",
		"STORAGE_BUCKET_COOKBOOK": "custom-bucket",
		"SSE_HEARTBEAT_SECONDS":   "5",
	}
	for k, v := range requiredEnv {
		env[k] = v
	}
	setEnv(t, env)

	cfg, err := config.Load()
	if err != nil {
		t.Fatalf("Load() unexpected error: %v", err)
	}

	if cfg.Port != 9090 {
		t.Errorf("Port: got %d, want 9090", cfg.Port)
	}
	if cfg.LogLevel != "debug" {
		t.Errorf("LogLevel: got %q, want %q", cfg.LogLevel, "debug")
	}
	if cfg.OpenAIChatModel != "gpt-4.1-2024-04-09" {
		t.Errorf("OpenAIChatModel: got %q", cfg.OpenAIChatModel)
	}
	if cfg.OpenAIImageModel != "dall-e-3" {
		t.Errorf("OpenAIImageModel: got %q", cfg.OpenAIImageModel)
	}
	if cfg.StorageBucketCookbook != "custom-bucket" {
		t.Errorf("StorageBucketCookbook: got %q", cfg.StorageBucketCookbook)
	}
	if cfg.SSEHeartbeatSeconds != 5 {
		t.Errorf("SSEHeartbeatSeconds: got %d, want 5", cfg.SSEHeartbeatSeconds)
	}
}

func TestLoad_MissingRequired_Errors(t *testing.T) {
	cases := []string{
		"SUPABASE_JWKS_URL",
		"SUPABASE_ISSUER",
		"SUPABASE_DB_URL",
		"SUPABASE_STORAGE_URL",
		"SUPABASE_SERVICE_ROLE_KEY",
		"OPENAI_API_KEY",
	}
	for _, missing := range cases {
		t.Run(missing, func(t *testing.T) {
			env := make(map[string]string, len(requiredEnv))
			for k, v := range requiredEnv {
				if k == missing {
					continue
				}
				env[k] = v
			}
			setEnv(t, env)
			// t.Setenv only sets — make sure the missing one isn't lingering
			// from the parent shell.
			t.Setenv(missing, "")

			if _, err := config.Load(); err == nil {
				t.Fatalf("Load() with %s unset: want error, got nil", missing)
			} else if !strings.Contains(err.Error(), missing) {
				t.Errorf("Load() error %q should name the missing var %q", err, missing)
			}
		})
	}
}

func TestLoad_AWSRegionRequiredOutsideDevelopment(t *testing.T) {
	env := map[string]string{}
	for k, v := range requiredEnv {
		env[k] = v
	}
	setEnv(t, env)
	t.Setenv("AWS_REGION", "")

	if _, err := config.Load(); err == nil {
		t.Fatal("Load() without AWS_REGION should error")
	}

	t.Setenv("SOUS_CHEF_ENV", "development")
	cfg, err := config.Load()
	if err != nil {
		t.Fatalf("Load() with SOUS_CHEF_ENV=development should succeed: %v", err)
	}
	if cfg.AWSRegion != "" {
		t.Errorf("AWSRegion in dev: got %q, want empty", cfg.AWSRegion)
	}
}

func TestLoad_RejectsBadPort(t *testing.T) {
	env := map[string]string{}
	for k, v := range requiredEnv {
		env[k] = v
	}
	setEnv(t, env)

	cases := map[string]string{
		"not-an-int": "not-an-int",
		"zero":       "0",
		"too-large":  "70000",
	}
	for name, raw := range cases {
		t.Run(name, func(t *testing.T) {
			t.Setenv("PORT", raw)
			if _, err := config.Load(); err == nil {
				t.Errorf("Load() with PORT=%q: want error, got nil", raw)
			}
		})
	}
}

func TestLoad_RejectsUnknownLogLevel(t *testing.T) {
	env := map[string]string{}
	for k, v := range requiredEnv {
		env[k] = v
	}
	setEnv(t, env)
	t.Setenv("LOG_LEVEL", "verbose")

	if _, err := config.Load(); err == nil {
		t.Error("Load() with LOG_LEVEL=verbose: want error, got nil")
	}
}
