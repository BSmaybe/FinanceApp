# Gamification + Motion Plan — Financial Cockpit

> **Phase 6** of the Financial Cockpit redesign roadmap.
> Companion spec to [`financial-cockpit-master-plan.md`](./financial-cockpit-master-plan.md).

---

## Principles

| Axis | Decision |
|------|----------|
| Tone | `balanced game layer` — progress and reinforcement, not entertainment |
| Placement | `везде понемногу` — distributed across tabs, no single "game screen" |
| Motion style | `subtle premium` — short, expensive-looking, functional |

The app is a financial tool first. Gamification exists to **retain**, create a **sense of progress**, and **reinforce healthy financial behaviour**. It must never feel like a casino or a children's game.

---

## Product Rules

### What earns XP and achievements
- Regular transaction capture
- Staying within budget
- Closing goals
- Paying off debts
- Planning behaviour (setting budgets, creating goals)
- Healthy streaks (consecutive days with at least one recorded transaction)

### What does NOT earn XP
- Spending volume. `big_spender` achievement **must be removed or replaced** with a finance-positive alternative (e.g. `mindful_spender` — stayed under budget for 3 months).
- Any behaviour that incentivises overspending, over-borrowing, or ignoring the budget.

### Motion rules
- Every animation must serve one of four functions: **reward reveal**, **progress fill**, **state transition**, or **micro-celebration**.
- Default path: `subtle` — spring timing, short duration (≤ 0.4 s).
- Reward moment: `expressive` — but capped at ≤ 0.8 s total, then returns to idle.
- No constant pulsing, no idle flashing, no casino-style feedback loops.
- Live Activity and Dynamic Island: **ActivityKit-safe only** — no custom animation frameworks, only `contentTransition` and system transitions.

---

## System Design

### Canonical layers

| Layer | Type | Role |
|-------|------|------|
| `GamificationEngine` | Computation | XP, level, streak calculation. Single source of truth for numeric state. |
| `AchievementStore` | Catalog | Defines all achievements, their unlock conditions, and ids. |
| `HeroProfileView` | Detail UI | Level, XP bar, streak calendar, full achievement list. |
| `HeroProfileCardView` | Compact UI | Progress teaser on Dashboard — level badge + XP ring + streak count. |
| `SuccessOverlayView` | Reward UI | Shared overlay for goal completion, debt payoff, level-up, first unlock. |
| `LiveActivityManager` | Orchestration | Milestone celebration triggers for Live Activity / Dynamic Island. |

### Achievement catalog — finance-safe set

Keep the following ids (rename display strings as needed):

| ID | Trigger |
|----|---------|
| `first_transaction` | First transaction recorded |
| `budget_keeper` | Stayed under budget in all categories for a full month |
| `debt_slayer` | Made a debt payment that closes or significantly reduces a debt |
| `goal_getter` | Completed a savings goal |
| `streak_7` | 7-day capture streak |
| `streak_30` | 30-day capture streak |
| `saver` | Monthly net income positive for 3 consecutive months |
| `debt_free` | All active debts paid off |
| `planner` | Set budgets for ≥ 3 categories in a single month |
| `legend` | Reached the highest XP level |

**Remove or replace**: `big_spender` (and any equivalent that rewards spending volume).

### Achievement unlock model — derived-first

The unlocked set **must be derived** from current data via `AchievementStore.checkUnlocked(transactions:goals:debts:budgets:)`.

`@AppStorage("unlockedAchievements")` is **only** allowed as a cache/legacy bridge for displaying "newly unlocked" notifications. It must not be the primary gate for whether an achievement shows as unlocked.

### ID alignment

Badge ids in `HeroProfileView` / `HeroProfileCardView` must match ids in `AchievementStore` exactly. No placeholder strings like `"achievement_1"` in UI code.

---

## Per-Tab Placement

| Tab | Gamification surface |
|-----|---------------------|
| **Dashboard** | `HeroProfileCardView` compact module (below hero financial metric), streak/level capsule, one rotating reward/insight card |
| **Transactions** | Save success burst on quick-add, streak reinforcement on capture, duplicate-free confirmation |
| **Analytics** | Progress framing for budgets/goals/planning — no celebratory motion for neutral events |
| **Accounts** | Achievement hooks for structure milestones (first account, multi-account) only, no recurring UI noise |
| **Settings** | Toggle/policy surface only. Not a primary gamification surface. |

### Dashboard constraint

`HeroProfileCardView` appears **below** the main net worth hero card. The financial metric is always the primary element. The gamification card is a secondary surface.

---

## Motion Spec

### In-app

| Surface | Motion |
|---------|--------|
| Quick Add (save) | Numeric text `contentTransition(.numericText())`, confirmation checkmark burst (scale + opacity, ≤ 0.35 s), "Captured" label fade |
| Goals / Debts (complete) | `SuccessOverlayView` — unify to one motion language: confetti drop + scale-in card + haptic `.success` |
| Dashboard (progress chips) | `.contentTransition(.numericText())` on XP/level counters, spring reveal on streak badge |
| HeroProfileView | XP bar fill (animated `trim`, spring easing), badge unlock reveal (scale from 0.6 + blur clear), streak dot activation (scale bounce) |

All durations:

| Type | Duration |
|------|----------|
| Micro feedback | ≤ 0.25 s |
| Progress fill | 0.4–0.6 s |
| Reward reveal | 0.5–0.8 s |
| Overlay dismiss | 0.3 s |

### Live Activity

Base: existing budget-progress animation stays.

Add finance-safe celebration states to `LiveActivityManager.CelebrationKind`:

```swift
enum CelebrationKind {
    case goalReached(name: String)
    case debtPaidOff(name: String)
    // v2 only — do not implement in Phase 6A/B:
    // case budgetMonthCompleted
}
```

Celebration flow:
1. Trigger celebration state (icon swap + accent colour shift + short label).
2. Hold for ≤ 3 s.
3. Return to default budget state automatically.

### Dynamic Island

- Compact / minimal: **one signal at a time**. Never show two competing stories.
- Milestone: icon swap → bounce → tone shift (accent colour) → short label (≤ 12 chars).
- After milestone: return to default budget display.
- No custom animation frameworks. Use `contentTransition` and system ActivityKit transitions only.

---

## Implementation Steps

### Phase 6A — Cleanup existing gamification model
- Remove or replace `big_spender` achievement from `AchievementStore`.
- Align all achievement ids between `AchievementStore` and hero UI.
- Replace `@AppStorage`-only unlock logic with `AchievementStore.checkUnlocked(...)` as primary source.
- Keep `@AppStorage("unlockedAchievements")` as cache/legacy bridge only.

### Phase 6B — Dashboard + Hero profile integration
- Connect `HeroProfileCardView` to live `GamificationEngine` data.
- Place `HeroProfileCardView` on Dashboard below hero financial card.
- Connect `HeroProfileView` to `GamificationEngine` + `AchievementStore` — remove all placeholder-only behaviour.

### Phase 6C — Reward system + achievements
- Introduce `RewardEvent` shared type for in-app overlay triggers:
  ```swift
  struct RewardEvent {
      enum Kind { case goalCompleted, debtPaidOff, levelUp, firstUnlock(id: String) }
      let kind: Kind
      let title: String
      let subtitle: String
  }
  ```
- Wire `SuccessOverlayView` to `RewardEvent` — one shared presenter for goal, debt, level-up, first unlock.
- Rebuild achievement list around healthy finance milestones (see catalog above).

### Phase 6D — Live Activity / Dynamic Island polish
- Add `CelebrationKind.goalReached` and `.debtPaidOff` to `LiveActivityManager`.
- Wire goal completion and debt payoff flows to trigger celebration + auto-return.
- Validate all Dynamic Island states (compact, minimal, expanded) against the signal rules above.

### Phase 6E — Cross-screen motion consistency
- Audit all save/confirm/complete actions across tabs.
- Apply unified motion language: spring timing, `symbolEffect`, `contentTransition`.
- Verify reduced-motion compatibility (`@Environment(\.accessibilityReduceMotion)`).

---

## Public Interfaces

| Type | Status | Notes |
|------|--------|-------|
| `HeroStats` | Keep as-is | Public output type from `GamificationEngine` |
| `Achievement` / `AchievementStore` | Keep, update catalog | Finance-safe set only |
| `LiveActivityManager.CelebrationKind` | Extend | Finance-safe milestone cases only |
| `RewardEvent` | New | Shared in-app overlay trigger type |
| `Transaction`, `Goal`, `Debt`, `Budget`, `Account` | Unchanged | No model changes in Phase 6 |

---

## Test Plan

### Data logic
- XP, level, streak correctly computed for: empty state, new user (1 transaction), power user (200+ transactions, multiple goals/debts closed).
- Achievements unlock only for finance-positive triggers.
- `big_spender` (or equivalent spending-volume reward) does not appear in UI or in `checkUnlocked` output.

### Dashboard
- `HeroProfileCardView` and hero financial card coexist without visual overload.
- Small screens (iPhone SE) and Dynamic Type (accessibility large) keep hierarchy readable.
- Dashboard section toggles do not break progress surfaces.

### Hero profile
- Correct level, XP progress, streak count, and unlocked achievements shown.
- No placeholder id mismatch between `AchievementStore` ids and displayed badges.

### Reward motion
- Save, goal complete, debt payoff, level-up each use one coherent motion language.
- Repeated rapid events do not stack broken overlays.
- `@Environment(\.accessibilityReduceMotion) == true` suppresses non-essential motion.

### Live Activity / Dynamic Island
- Budget progress animation still works after `CelebrationKind` extension.
- Goal / debt celebrations appear briefly and reset to budget state.
- No visual corruption in compact / minimal / expanded island states.

### Cross-cutting
- Light and dark themes.
- `en`, `ru`, `kk` locales.
- Reduced motion mode.
- Tests remain aligned with [TESTING.md](../../TESTING.md).

---

## Assumptions

- Gamification is a permanent product feature, not a temporary experiment.
- No single "gamification screen" — the system is distributed, with `Dashboard` and `HeroProfileView` as the two primary surfaces.
- Existing work (`GamificationEngine`, `AchievementStore`, `SuccessOverlayView`, `HeroProfileView`) is the foundation, not throwaway code.
- Documentation is written before code. Implementation follows the phase roadmap above.
- No new motion framework is introduced. The stack is: SwiftUI transitions, `symbolEffect`, `contentTransition`, spring timing, ActivityKit-safe updates.
