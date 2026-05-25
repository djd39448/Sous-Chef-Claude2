// Package domain defines the Go types that mirror the contract §4 data
// model. Each type is the wire shape the API emits and the row shape the
// store package reads — one type, two views, no DTO/Model split.
//
// The top-level field names are camelCase per contract §3.1 wire
// convention; the JSONB sub-document field names are snake_case verbatim
// (contract §3.1: "JSONB sub-document fields are returned verbatim with
// the underlying snake_case keys — they are the same shape the AI tool
// calls produce and consume").
//
// Depends on: standard library (time, encoding/json), google/uuid.
// Depended on by: internal/api (handlers serialise these to the wire),
// internal/store (decoders scan rows into these types).
// Why it exists: the contract defines one canonical shape per resource;
// duplicating that shape into per-package DTOs would be the source of the
// drift the contract document exists to prevent. One type, used at both
// boundaries, kept in lock-step with the contract by code review.
package domain

import (
	"time"

	"github.com/google/uuid"
)

// FoodItem mirrors contract §4.2 (the Canonical Food Object). The wire
// JSON keys are camelCase per §3.1; the embedded JSONB sub-documents
// (Category, UsageContext, etc.) keep their snake_case keys verbatim.
type FoodItem struct {
	ID             uuid.UUID      `json:"id"`
	UserID         uuid.UUID      `json:"userId"`
	CanonicalName  string         `json:"canonicalName"`
	DisplayName    string         `json:"displayName"`
	Quantity       *Quantity      `json:"quantity,omitempty"`
	Category       Category       `json:"category"`
	Attributes     map[string]any `json:"attributes"`
	Flexibility    Flexibility    `json:"flexibility"`
	UsageContext   UsageContext   `json:"usageContext"`
	InventoryState InventoryState `json:"inventoryState"`
	Sourcing       Sourcing       `json:"sourcing"`
	Metadata       Metadata       `json:"metadata"`
	CreatedAt      time.Time      `json:"createdAt"`
	UpdatedAt      time.Time      `json:"updatedAt"`
}

// Quantity is the JSONB { amount, unit } shape. Nullable on the row —
// callers see a nil pointer.
type Quantity struct {
	Amount float64 `json:"amount"`
	Unit   string  `json:"unit"`
}

// Category is the JSONB { primary, secondary? } shape. Primary is one of
// the nine-value enum (contract §4.2 "category_primary_known" CHECK).
type Category struct {
	Primary   string `json:"primary"`
	Secondary string `json:"secondary,omitempty"`
}

// Flexibility is the JSONB { substitution_allowed, acceptable_variants,
// strict } shape from contract §4.2.
type Flexibility struct {
	SubstitutionAllowed bool     `json:"substitution_allowed"`
	AcceptableVariants  []string `json:"acceptable_variants"`
	Strict              bool     `json:"strict"`
}

// UsageContext is the JSONB { role, required?, recipe_ids?, meal_plan_id?,
// shopping_list_id? } shape. Role is one of inventory|shopping|planned|
// ingredient — per ADR-0009 only inventory and shopping are written by
// v1 code, but the constraint admits all four.
type UsageContext struct {
	Role           string      `json:"role"`
	Required       *bool       `json:"required,omitempty"`
	RecipeIDs      []uuid.UUID `json:"recipe_ids,omitempty"`
	MealPlanID     *uuid.UUID  `json:"meal_plan_id,omitempty"`
	ShoppingListID *uuid.UUID  `json:"shopping_list_id,omitempty"`
}

// InventoryState is the JSONB { status, on_hand_amount, last_confirmed }
// shape. status is one of confirmed|likely|unknown|out.
type InventoryState struct {
	Status        string     `json:"status"`
	OnHandAmount  *float64   `json:"on_hand_amount"`
	LastConfirmed *time.Time `json:"last_confirmed"`
}

// Sourcing is the JSONB { store_affinity, bulk_allowed, generic_ok } shape.
type Sourcing struct {
	StoreAffinity *string `json:"store_affinity"`
	BulkAllowed   bool    `json:"bulk_allowed"`
	GenericOK     bool    `json:"generic_ok"`
}

// Metadata is the JSONB { created_by, confidence } shape. created_by is
// one of "ai" or "user".
type Metadata struct {
	CreatedBy  string  `json:"created_by"`
	Confidence float64 `json:"confidence"`
}
