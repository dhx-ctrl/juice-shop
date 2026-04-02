#!/usr/bin/env python3
"""
dojo_log_response.py  —  Parse and log a DefectDojo import/reimport-scan response.

Usage: python3 dojo_log_response.py <label> <json_file>

Reads the JSON response written to <json_file>, extracts the key metrics
(test_id, total findings imported, new findings), and prints a one-line
summary.  Also dumps the top-level response keys so the structure is visible
in CI logs — useful for diagnosing unknown DD versions.
"""
import json
import sys

label    = sys.argv[1]
tmp_path = sys.argv[2]

with open(tmp_path) as fh:
    raw = fh.read().strip()

# ── Parse ──────────────────────────────────────────────────────────────────
try:
    d = json.loads(raw)
except Exception as e:
    print(f"[{label}] ERROR parsing DD response: {e}")
    print(f"RAW (first 800 chars): {raw[:800]}")
    sys.exit(0)

# Always show top-level keys — helps identify response schema across DD versions
top_keys = list(d.keys()) if isinstance(d, dict) else type(d).__name__
print(f"[{label}] DEBUG response keys: {top_keys}")

# ── Error check ────────────────────────────────────────────────────────────
errors = (
    d.get("error")
    or d.get("message")
    or d.get("detail")
    or d.get("non_field_errors")
)
if errors:
    print(f"[{label}] WARNING DD reported: {errors}")
    sys.exit(0)

# ── test_id ────────────────────────────────────────────────────────────────
test_val = d.get("test")
tid = test_val.get("id") if isinstance(test_val, dict) else test_val

# ── Findings counts — field names vary by DD version ──────────────────────
# v2.x:  d["statistics"]["after"]["findings"]["total"] / ["opened"]
# older: d["total_imported_findings"], d["findings_count"]
stats      = d.get("statistics") or {}
after      = stats.get("after") or {}
findings_s = after.get("findings") or {}

total_f = (
    d.get("total_imported_findings")
    or d.get("findings_count")
    or findings_s.get("total")
    or after.get("total")
    or stats.get("total")
    or "?"
)
new_f = (
    findings_s.get("opened")
    or after.get("opened")
    or d.get("new_findings")
    or "?"
)

print(f"[{label}] OK  test_id={tid} | total_imported={total_f} | new={new_f}")
