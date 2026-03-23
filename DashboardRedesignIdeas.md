# Dashboard Redesign — Top 5 Ideas

> **Problem**: `DashboardView.swift` is 1 487 lines and renders up to 10 sections
> simultaneously — hero, accounts scroll, FAB + shortcuts, budget rings grid,
> debts summary, upcoming payments scroll, recent activity list — causing visual
> overload and competing scroll directions.

---

## Pain-points addressed by every idea

| # | Problem |
|---|---------|
| 1 | Two independent horizontal scrolls (accounts + upcoming) inside one vertical scroll |
| 2 | Hero packs 6 elements: net worth, insight text, month nav, 3 stat chips |
| 3 | Budget rings, debts summary, upcoming payments all visible at once |
| 4 | Quick-actions FAB overlaps content area |
| 5 | All sections permanently expanded — zero progressive disclosure |

---

## Idea 1 — "Focus Strip" (collapsible rows)

**Concept**: shrink the hero to Net Worth + month arrows (56 pt tall).
Every section below becomes a **collapsed summary row** by default.
Tap to expand inline. Visual noise drops ~70 % immediately.

```
┌─────────────────────────────────┐
│  Net Worth  $12 400   < Mar >   │  ← 56 pt hero
├─────────────────────────────────┤
│ 💳  Accounts (3)            ›   │
│ 🎯  Budgets — 2 at risk     ›   │
│ 📅  Upcoming — 2 this week  ›   │
│ 💸  Recent — last: −$45     ›   │
└─────────────────────────────────┘
```

**Implementation**: replace each section body with a `DisclosureGroup`-style
wrapper controlled by `@State var expanded`. Reuse all existing helper
functions (`budgetPressureList()`, `buildUpcomingItems()`, etc.) unchanged.

**Effort**: Medium (no model changes, pure layout refactor).
**Recommendation**: best starting point — safe, backward-compatible.

---

## Idea 2 — "Page Cards" (horizontal paging below hero)

**Concept**: keep the hero as-is, replace the long vertical scroll below it
with a **horizontal `TabView(.page)`** — one page per topic:
Accounts / Budgets / Upcoming / Activity.
Navigation dots show position; no nested horizontal scrolls.

```
┌──────────────────────────────────┐
│        Net Worth  $12 400        │
│   ↑ $800 this month  •  Mar 26   │
├──────────────────────────────────┤
│  ←     [ BUDGETS PAGE ]     →   │
│                                  │
│   Food        ████░  68%  🟡    │
│   Transport   ██░░   40%  🟢    │
│   Dining      █████  95%  🔴    │
│                                  │
│              ● ○ ○ ○            │
└──────────────────────────────────┘
```

**Implementation**: wrap the four main sections in
`TabView(selection: $dashPage) { }.tabViewStyle(.page(indexDisplayMode: .always))`.
Each page is an extracted subview.

**Effort**: Low–medium (no model changes, mainly layout swap).

---

## Idea 3 — "Smart Today" (context-aware single focus)

**Concept**: show **one primary card** chosen by the day's context, using
the priority logic that already exists in `heroInsight()`:

1. Budget near/over limit → Budget Alert card
2. Payment due today/tomorrow → Upcoming card
3. Otherwise → Net Worth + savings rate

A compact icon-chip row at the bottom lets the user jump to any section.

```
┌──────────────────────────────────┐
│  Mon, 23 Mar 2026                │
│                                  │
│  ╔═══ TODAY'S FOCUS ══════╗     │
│  ║  🔴  Food budget  92%  ║     │
│  ║  $230 spent of $250    ║     │
│  ╚════════════════════════╝     │
│                                  │
│  [💳] [📅] [💸] [🎯]  [＋]    │
└──────────────────────────────────┘
```

**Implementation**: new `todayFocusCard()` view; reuse
`budgetPressureList()` + `buildUpcomingItems()`. Icon chips are `Button`s
that set `@State var selectedTab` on the parent `TabView`.

**Effort**: Medium (new view logic, existing data helpers unchanged).

---

## Idea 4 — "Widget Grid" (configurable 2-column grid)

**Concept**: replace fixed sections with a **2 × N grid of compact widgets**.
Each widget is a uniform-height card. `DashboardSettingsView` (already has
`AppStorage` visibility flags) gains a widget-order picker.

Available widgets: NetWorth, TopBudget, NextPayment, DebtProgress,
SavingsRate, RecentTransaction, GoalProgress.

```
┌──────────────────────────────────┐
│        Net Worth  $12 400        │
├───────────────┬──────────────────┤
│  Top Budget   │  Next Payment    │
│  Food  92%    │  Netflix  $15    │
│  🔴           │  in 3 days       │
├───────────────┼──────────────────┤
│  Debt left    │  Savings rate    │
│  $3 200  ↓    │  22%  ↑          │
└───────────────┴──────────────────┘
```

**Implementation**: `LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())])`.
Each widget is its own extracted view. Order stored in `AppStorage` as a
comma-separated key list.

**Effort**: High (new widget views + settings UI; drag-to-reorder optional v2).

---

## Idea 5 — "Layered Sheet" (pull-up bottom sheet)

**Concept**: hero covers most of the screen with only Net Worth + one insight.
A **native bottom sheet** (iOS 16+ `presentationDetents`) slides up in three
layers of detail:

| Detent | Content |
|--------|---------|
| Small (120 pt) | Account chips row |
| Medium (50 %) | Budget rings + upcoming payments |
| Large (full) | Recent activity list |

```
╔══════════════════════════════════╗  ← full-screen gradient
║                                  ║
║        Net Worth  $12 400        ║
║     ↑ $800  •  savings 22 %      ║
║                                  ║
╠══════════════════════════════════╣  ← drag handle (small detent)
║  💳 Checking  💳 Savings  💵 …  ║
╚══════════════════════════════════╝
```

**Implementation**: wrap content in `.sheet(isPresented: .constant(true))`
with `.presentationDetents([.height(120), .medium, .large])`
and `.presentationBackgroundInteraction(.enabled)`.

**Effort**: Medium (SwiftUI-native, iOS 16+, no model changes).

---

## Summary & Recommended Path

| Idea | Clutter Reduction | Effort | Risk |
|------|:-----------------:|--------|------|
| 1 — Focus Strip   | ★★★★★ | Medium | Low  |
| 2 — Page Cards    | ★★★★☆ | Low    | Low  |
| 3 — Smart Today   | ★★★★☆ | Medium | Low  |
| 4 — Widget Grid   | ★★★★☆ | High   | Med  |
| 5 — Layered Sheet | ★★★☆☆ | Medium | Low  |

**Start with Idea 1** (Focus Strip) — it cuts visible content by ~70 % with
zero model risk and makes all other ideas easier to layer on top.
Combine with **Idea 2** (page cards inside an expanded row) as a fast follow-up.
