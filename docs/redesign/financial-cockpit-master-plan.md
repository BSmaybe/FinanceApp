# Financial Cockpit — Master Redesign Plan

> Single reference document for all redesign phases.
> Original ideas source: [`DashboardRedesignIdeas.md`](../../DashboardRedesignIdeas.md).

---

## Problem Statement

`DashboardView.swift` (originally 1 487 lines) rendered up to 10 sections simultaneously — hero, accounts scroll, FAB + shortcuts, budget rings grid, debts summary, upcoming payments scroll, recent activity list — causing visual overload and competing scroll directions.

| # | Pain-point |
|---|------------|
| 1 | Two independent horizontal scrolls (accounts + upcoming) inside one vertical scroll |
| 2 | Hero packed 6 elements: net worth, insight text, month nav, 3 stat chips |
| 3 | Budget rings, debts summary, upcoming payments all visible at once |
| 4 | Quick-actions FAB overlapped content area |
| 5 | All sections permanently expanded — zero progressive disclosure |

---

## Phase Roadmap

| Phase | Name | Status |
|-------|------|--------|
| **Phase 1** | Focus Strip — collapsible rows | ✅ Shipped |
| **Phase 2** | Page Cards inside expanded row | Deferred |
| **Phase 3** | Smart Today — context-aware focus | Deferred |
| **Phase 4** | Widget Grid — configurable 2-column | Deferred |
| **Phase 5** | Full Dashboard Redesign (greeting + hero card + quick actions + insights) | 🚧 In progress |
| **Phase 6** | Gamification + Motion | 📋 Specced |

---

## Phase 1 — Focus Strip

**Concept**: shrink hero to Net Worth + month arrows (56 pt tall). Every section below becomes a collapsed summary row by default. Tap to expand inline. Visual noise drops ~70 % immediately.

**Implementation**: each section wrapped in a `collapsibleSection()` helper with `@State var expanded`. All existing data helpers (`budgetPressureList()`, `buildUpcomingItems()`, etc.) unchanged.

**Effort**: Medium. **Risk**: Low.

---

## Phase 2 — Page Cards

**Concept**: keep the hero, replace the vertical scroll below it with a horizontal `TabView(.page)` — one page per topic: Accounts / Budgets / Upcoming / Activity.

**Effort**: Low–Medium. **Risk**: Low. **Status**: Deferred pending Phase 5 validation.

---

## Phase 3 — Smart Today

**Concept**: show one primary card chosen by daily context (budget at risk → budget alert; payment due → upcoming card; otherwise → net worth + savings rate). Icon-chip row at bottom for quick navigation.

**Effort**: Medium. **Risk**: Low. **Status**: Deferred.

---

## Phase 4 — Widget Grid

**Concept**: replace fixed sections with a 2×N grid of compact, uniform-height widget cards. `DashboardSettingsView` gains a widget-order picker.

**Effort**: High. **Risk**: Medium. **Status**: Deferred.

---

## Phase 5 — Full Dashboard Redesign

**Target design**: dark/themed background, distributed layout with clear hierarchy.

### Layout structure

```
ScrollView (LazyVStack, spacing 20)
├── Greeting section
│     👋 Hi [Name]  •  date  •  ⚙ settings button
├── Hero card  (fabGradient background, rounded 24)
│     month nav  •  "Net Worth" label  •  large amount
│     sparkline (last 6 months)
│     income chip  •  expense chip  •  monthly delta badge
├── Quick actions row  (primaryAccent tint card)
│     [+ Payment]  [History]  [Accounts]  [Forecast]
├── Latest Transactions block  (surface card)
│     header + "See all" →  •  top 3 rows
└── Insights  (horizontal scroll)
      Budget risk card  •  Upcoming payment card
      Savings rate card  •  Goals/Debts/Subscriptions shortcuts
```

### Key rules
- `HeroProfileCardView` (Phase 6) will be inserted between Quick Actions and Latest Transactions — **after** Phase 6B lands.
- All business logic (`stats()`, `budgetPressureList()`, `buildUpcomingItems()`, notifications, Live Activity, widget sync) is preserved unchanged.
- `@AppStorage("heroName")` / `@AppStorage("heroEmoji")` drive the greeting.
- Net worth sparkline is computed on the fly from the last 6 months of transactions — not stored.

### New localization keys (Phase 5)
`"Hi %@"`, `"there"`, `"Latest Transactions"`, `"See all"`, `"Over budget!"`, `"Over income this month"`, `"Saved %lld%% of income"` — added to `en`, `ru`, `kk`.

---

## Phase 6 — Gamification + Motion

> Full spec: [`gamification-motion-plan.md`](./gamification-motion-plan.md)

### Direction

| Axis | Decision |
|------|----------|
| Tone | `balanced game layer` |
| Placement | `везде понемногу` — distributed, not one screen |
| Motion style | `subtle premium` |

### Sub-phases

| Sub-phase | Scope |
|-----------|-------|
| **6A** | Cleanup existing gamification model — remove `big_spender`, align ids, derived-first unlock logic |
| **6B** | Dashboard + Hero profile integration — `HeroProfileCardView` on Dashboard, `HeroProfileView` wired to live data |
| **6C** | Reward system + achievements — `RewardEvent` type, unified `SuccessOverlayView`, finance-safe achievement catalog |
| **6D** | Live Activity / Dynamic Island polish — `CelebrationKind` extension, goal/debt celebration states |
| **6E** | Cross-screen motion consistency — audit all tabs, spring/`symbolEffect`/`contentTransition`, reduced-motion |

### Canonical system components

| Component | Role |
|-----------|------|
| `GamificationEngine` | XP / level / streak computation |
| `AchievementStore` | Finance-safe achievement catalog |
| `HeroProfileView` | Detail hub: level, XP, streak, achievements |
| `HeroProfileCardView` | Dashboard compact progress surface |
| `SuccessOverlayView` | Shared reward overlay |
| `LiveActivityManager` | Milestone celebration orchestration |

### Finance-safe achievement ids
`first_transaction`, `budget_keeper`, `debt_slayer`, `goal_getter`, `streak_7`, `streak_30`, `saver`, `debt_free`, `planner`, `legend`.

**Removed**: `big_spender` (spending-volume reward).

### Public interfaces added in Phase 6
- `LiveActivityManager.CelebrationKind` — extended with `.goalReached`, `.debtPaidOff`.
- `RewardEvent` — new shared in-app overlay trigger type.
- No changes to `Transaction`, `Goal`, `Debt`, `Budget`, `Account`.

---

## Architecture Constraints (all phases)

- **No new motion framework.** Stack: SwiftUI transitions, `symbolEffect`, `contentTransition`, spring timing, ActivityKit-safe updates.
- **No model mutations for display state.** Derived values (balances, totals, XP, streaks) are always computed from source data — never stored as mutable counters.
- **AppTheme system.** All colours via `AppTheme.xxx`. No hardcoded `Color(.red)` etc.
- **Localization.** Every new user-visible string added to `en`, `ru`, `kk`.
- **SwiftData migration safety.** New model fields must have default values.

---

## Related Documents

- [`DashboardRedesignIdeas.md`](../../DashboardRedesignIdeas.md) — original 5-idea brief
- [`gamification-motion-plan.md`](./gamification-motion-plan.md) — Phase 6 companion spec
- [`TESTING.md`](../../TESTING.md) — test flow reference
- [`CLAUDE.md`](../../CLAUDE.md) — code style and build rules
