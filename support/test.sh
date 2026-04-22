#!/usr/bin/env bash
# Test the CSV→JSON converter.
# Normalizes random UUIDs to "ID" so we can diff deterministically.
set -euo pipefail

cd "$(dirname "$0")"

python3 convert.py --in test.csv --out out.json

# Normalize: replace UUID-shaped IDs with "ID" and format consistently
jq '[.[] | .id = "ID"]' out.json > out_normalized.json
jq '.' expected.json > expected_normalized.json

if diff -u expected_normalized.json out_normalized.json; then
  echo "PASS: output matches expected"
  rm -f out.json out_normalized.json expected_normalized.json
  exit 0
else
  echo "FAIL: output does not match expected"
  rm -f out_normalized.json expected_normalized.json
  exit 1
fi
