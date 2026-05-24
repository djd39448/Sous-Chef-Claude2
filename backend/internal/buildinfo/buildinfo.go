// Package buildinfo carries the values that identify which build of the
// sous-chef-api binary is running. The values default to "dev" / "unknown" so
// a `go run` from a developer's checkout still produces meaningful logs;
// release builds overwrite them via -ldflags at link time.
//
// Depends on: nothing. Pure data, no I/O — safe to import from any layer.
// Depended on by: cmd/sous-chef-api (logs the values at boot and exposes them
// on the /healthz response), internal/server (writes them to a response
// header for operator diagnostics).
// Why it exists: when a production /healthz returns ok we still need to know
// which commit is answering. Stamping the values at link time and exposing
// them at the edge is the cheapest way to answer "what's actually running".
package buildinfo

// Version is the human-readable build identifier — typically the short git
// SHA, or "dev" for an uninstrumented developer build. Set with
// -ldflags="-X github.com/djd39448/Sous-Chef-Claude2/backend/internal/buildinfo.Version=<sha>".
var Version = "dev"

// BuildTime is the RFC 3339 UTC timestamp at which the binary was linked.
// Set with -ldflags="-X github.com/djd39448/Sous-Chef-Claude2/backend/internal/buildinfo.BuildTime=<ts>".
// "unknown" in a non-release build.
var BuildTime = "unknown"
