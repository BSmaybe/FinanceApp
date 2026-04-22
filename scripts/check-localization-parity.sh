#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STRINGS_DIR="$ROOT_DIR/FinanceApp"
LOCALES=("en" "ru" "kk")

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

extract_keys() {
  local file="$1"
  sed -n 's/^"\(.*\)"[[:space:]]*=.*/\1/p' "$file" | sort -u
}

extract_raw_keys() {
  local file="$1"
  sed -n 's/^"\(.*\)"[[:space:]]*=.*/\1/p' "$file"
}

echo "Checking localization key parity..."
for locale in "${LOCALES[@]}"; do
  file="$STRINGS_DIR/${locale}.lproj/Localizable.strings"
  if [[ ! -f "$file" ]]; then
    echo "Missing file: $file" >&2
    exit 1
  fi

  extract_keys "$file" > "$tmp_dir/${locale}.keys"
  extract_raw_keys "$file" | sort | uniq -d > "$tmp_dir/${locale}.dup"

  total_keys="$(wc -l < "$tmp_dir/${locale}.keys" | tr -d ' ')"
  echo "  ${locale}: ${total_keys} unique keys"

  if [[ -s "$tmp_dir/${locale}.dup" ]]; then
    echo "Warning: duplicate keys in ${locale}.lproj/Localizable.strings:" >&2
    cat "$tmp_dir/${locale}.dup" >&2
  fi
done

base_locale="en"
status=0

for locale in "${LOCALES[@]}"; do
  [[ "$locale" == "$base_locale" ]] && continue

  missing_in_locale="$(comm -23 "$tmp_dir/${base_locale}.keys" "$tmp_dir/${locale}.keys" || true)"
  extra_in_locale="$(comm -13 "$tmp_dir/${base_locale}.keys" "$tmp_dir/${locale}.keys" || true)"

  if [[ -n "$missing_in_locale" ]]; then
    echo
    echo "Keys missing in ${locale} (present in ${base_locale}):" >&2
    echo "$missing_in_locale" >&2
    status=1
  fi

  if [[ -n "$extra_in_locale" ]]; then
    echo
    echo "Extra keys in ${locale} (not in ${base_locale}):" >&2
    echo "$extra_in_locale" >&2
    status=1
  fi
done

if [[ "$status" -ne 0 ]]; then
  exit "$status"
fi

echo "Localization parity OK for: ${LOCALES[*]}"
