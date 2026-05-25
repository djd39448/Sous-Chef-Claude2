//  IngredientsRow.swift
//
//  The single-row view rendered for each FoodItem in the Plan tab's
//  ingredients list.
//
//  Depends on:     SwiftUI and Domain.FoodItem.
//  Depended on by: IngredientsListView (uses one per row).
//  Why it exists:  dc-03 says "extract subviews aggressively — one
//                  reusable view per file." A row is a small, focused
//                  subview with its own accessibility and layout
//                  concerns; keeping it separate makes the list view's
//                  body short and a Preview block possible without
//                  pulling the full network surface.

import Domain
import SwiftUI

struct IngredientsRow: View {
    /// item is the FoodItem this row renders. Passed by value (struct
    /// copy) per dc-03 "pass a subview the minimum data it needs".
    let item: FoodItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.body)
                    .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    categoryChip
                    statusBadge
                    if let quantity = item.quantity {
                        Text(formatted(quantity: quantity))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// categoryChip renders the FoodCategory.primary as a small capsule
    /// in the same color family across the app. The label is the raw
    /// enum string (lowercase) per the wire vocabulary; future visual
    /// polish (F2) may humanize it.
    private var categoryChip: some View {
        Text(item.category.primary.rawValue)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    /// statusBadge renders the inventory status as a colored dot plus
    /// label. The four statuses get distinct colors so a quick scan
    /// of the list shows "what's low" at a glance.
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(item.inventoryState.status.rawValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }

    private var statusColor: Color {
        switch item.inventoryState.status {
        case .confirmed: .green
        case .likely: .yellow
        case .unknown: .gray
        case .out: .red
        }
    }

    /// formatted renders a FoodQuantity as "<amount> <unit>". Decimal's
    /// String(describing:) is locale-invariant — exactly what we want
    /// because the unit is the AI's free-form string already.
    private func formatted(quantity: FoodQuantity) -> String {
        "\(quantity.amount) \(quantity.unit)"
    }

    /// accessibilityLabel collapses the visible chips and badges into
    /// one spoken phrase for VoiceOver. Per dc-03 every interactive
    /// element needs a meaningful label; rows are not buttons here
    /// (Week 2 ships read-only) but the row is announced as a unit.
    private var accessibilityLabel: String {
        var parts = [item.displayName, "category \(item.category.primary.rawValue)"]
        parts.append("status \(item.inventoryState.status.rawValue)")
        if let quantity = item.quantity {
            parts.append("quantity \(formatted(quantity: quantity))")
        }
        return parts.joined(separator: ", ")
    }
}
