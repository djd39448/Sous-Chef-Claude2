// food_items.go — store-side reads of the CFO table. Only the
// inventory-listing query lives here for now; insert/update paths land
// in Phase G when the AI tool dispatcher writes through this package.
//
// The handler-facing seam is FoodItemReader — a one-method interface
// in the consumer package (internal/api/ingredients.go) — so the API
// package can substitute a deterministic fake at test time without
// pulling in pgx.
//
// All SQL here runs INSIDE a transaction opened by Pool.WithClaims;
// the caller passes the pgx.Tx in. The functions never touch the pool
// directly so the JWT-claim GUC (and therefore RLS) is always in scope.

package store

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/jackc/pgx/v5"

	"github.com/djd39448/Sous-Chef-Claude2/backend/internal/domain"
)

// ListInventory returns the caller's CFO inventory rows. Per contract
// §5.5 + ADR-0009 the filter is:
//
//   - usage_context.role = 'inventory'
//   - inventory_state.status != 'out'
//
// The user-id filter is NOT in the SQL; it is enforced by the RLS policy
// the data track wrote (ADR-0011). The handler may pass any pgx.Tx — in
// production this is the Tx Pool.WithClaims opened with the JWT user id;
// in tests against an in-memory fake the Tx parameter is unused.
//
// Rows are ordered by display_name to give the iOS client a stable list
// without requiring it to sort.
func ListInventory(ctx context.Context, tx pgx.Tx) ([]domain.FoodItem, error) {
	const q = `
		SELECT
			id, user_id, canonical_name, display_name,
			quantity, category, attributes, flexibility,
			usage_context, inventory_state, sourcing, metadata,
			created_at, updated_at
		FROM food_items
		WHERE usage_context->>'role' = 'inventory'
		  AND inventory_state->>'status' <> 'out'
		ORDER BY display_name
	`
	rows, err := tx.Query(ctx, q)
	if err != nil {
		return nil, fmt.Errorf("store.ListInventory: query: %w", err)
	}
	defer rows.Close()

	items := make([]domain.FoodItem, 0)
	for rows.Next() {
		item, err := scanFoodItem(rows)
		if err != nil {
			return nil, fmt.Errorf("store.ListInventory: scan: %w", err)
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("store.ListInventory: rows: %w", err)
	}
	return items, nil
}

// scanFoodItem decodes one row into a domain.FoodItem. Each JSONB column
// is read as []byte and unmarshalled into the typed sub-document; this
// keeps the type definitions in domain authoritative and out of pgx's
// reach.
func scanFoodItem(row pgx.Row) (domain.FoodItem, error) {
	var (
		item                                         domain.FoodItem
		qty, cat, attrs, flex, usage, inv, src, meta []byte
	)
	if err := row.Scan(
		&item.ID, &item.UserID, &item.CanonicalName, &item.DisplayName,
		&qty, &cat, &attrs, &flex,
		&usage, &inv, &src, &meta,
		&item.CreatedAt, &item.UpdatedAt,
	); err != nil {
		return domain.FoodItem{}, err
	}

	if len(qty) > 0 && !isJSONNull(qty) {
		var q domain.Quantity
		if err := json.Unmarshal(qty, &q); err != nil {
			return domain.FoodItem{}, fmt.Errorf("quantity: %w", err)
		}
		item.Quantity = &q
	}
	if err := json.Unmarshal(cat, &item.Category); err != nil {
		return domain.FoodItem{}, fmt.Errorf("category: %w", err)
	}
	if err := json.Unmarshal(attrs, &item.Attributes); err != nil {
		return domain.FoodItem{}, fmt.Errorf("attributes: %w", err)
	}
	if err := json.Unmarshal(flex, &item.Flexibility); err != nil {
		return domain.FoodItem{}, fmt.Errorf("flexibility: %w", err)
	}
	if err := json.Unmarshal(usage, &item.UsageContext); err != nil {
		return domain.FoodItem{}, fmt.Errorf("usage_context: %w", err)
	}
	if err := json.Unmarshal(inv, &item.InventoryState); err != nil {
		return domain.FoodItem{}, fmt.Errorf("inventory_state: %w", err)
	}
	if err := json.Unmarshal(src, &item.Sourcing); err != nil {
		return domain.FoodItem{}, fmt.Errorf("sourcing: %w", err)
	}
	if err := json.Unmarshal(meta, &item.Metadata); err != nil {
		return domain.FoodItem{}, fmt.Errorf("metadata: %w", err)
	}

	return item, nil
}

// isJSONNull reports whether the raw JSONB bytes encode a SQL NULL
// surfaced as the JSON token `null`. pgx returns a nil-length byte slice
// for SQL NULL, so this is the belt to the suspenders.
func isJSONNull(b []byte) bool {
	if len(b) != 4 {
		return false
	}
	return string(b) == "null"
}
