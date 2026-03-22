# Swift / SwiftUI Code Rules for FinanceApp

## Common compiler warnings to avoid

- **`var` → `let`**: Always use `let` unless the variable is actually mutated. Never declare `var` speculatively.
- **Unused variables**: Every declared variable must be used. If result is intentionally discarded, use `_ =`.
- **Unreachable code**: No code after `return`/`throw` in a branch.
- **Implicit `self`**: Inside closures capture `self` explicitly only when required. Don't add `[weak self]` unless there's an actual retain cycle.

## Swift style

- Use `let` by default, `var` only when mutation is needed.
- Prefer `guard let` / `guard else return` over nested `if let`.
- Prefer `if let x` (short form, Swift 5.7+) over `if let x = x`.
- Use `Decimal` for all money values, never `Double` or `Float`.
- Format money with `CurrencyFormatter.string(from:)`.
- Round `Decimal` results before displaying (avoid 0.999999999 artifacts).

## SwiftUI style

- Use `AppTheme.xxx` for all colors — never hardcode `Color(.red)` etc.
- Use `String(localized: "Key")` for every user-visible string — no raw string literals in views.
- Prefer `LabeledContent` for key/value rows in `Form`.
- Keep view body under ~80 lines; extract sub-views or computed `var` properties.
- Use `.foregroundStyle` not `.foregroundColor` (deprecated).

## Localization

- Every new user-visible string must be added to all 3 `.strings` files: `en`, `ru`, `kk`.
- Key = English text exactly as used in `String(localized: "Key")`.
- Format specifiers: use `%lld` for `Int`/`Int64`, `%@` for `String`, `%d` for `Int32`.
- Positional args for multi-arg strings: `%1$lld`, `%2$lld`.

## SwiftData

- New model fields must have default values to avoid migration errors: `var field: Int = 0`.
- Never delete/rename a `@Model` property without a migration plan.
- Derived values (balances, totals) must be computed from transactions — not stored as mutable counters.

## Project registration

- Every new `.swift` file must be added to `project.pbxproj` with both a PBXFileReference and a PBXBuildFile entry.
- Use sequential hex UUIDs (`F1C001`, `F1C002`, ...) to avoid conflicts.
- New files go in the correct group matching their folder (`Views/`, `Utils/`, `Models/`).

## Build verification

- Always run the build command after any code change before reporting "done":
  ```
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -scheme FinanceApp \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    build 2>&1 | tail -20
  ```
- Zero errors AND zero warnings is the target. Fix all warnings, not just errors.
