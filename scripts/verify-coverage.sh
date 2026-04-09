#!/usr/bin/env bash
set -euo pipefail

# Power Mapper — Tier 6: Coverage Verification
# Cross-references inventory against Tier 2 analysis outputs.
# Every file in the inventory must appear in at least one chunk analysis.

AUDIT_DIR=".planning/audit"
INV_DIR="$AUDIT_DIR/inventory"
FILES_DIR="$AUDIT_DIR/files"

if [[ ! -f "$INV_DIR/all_files.tsv" ]]; then
  echo "ERROR: No inventory found at $INV_DIR/all_files.tsv"
  echo "Run the inventory script first."
  exit 1
fi

if [[ ! -d "$FILES_DIR" ]] || [[ -z "$(ls -A "$FILES_DIR" 2>/dev/null)" ]]; then
  echo "ERROR: No Tier 2 analysis files found at $FILES_DIR/"
  echo "Run the file analysis agents first."
  exit 1
fi

echo "=== Power Mapper: Tier 6 Coverage Verification ==="

TOTAL_FILES=$(wc -l < "$INV_DIR/all_files.tsv" | tr -d ' ')
ANALYZED=0
MISSED=0

: > "$AUDIT_DIR/missed_files.txt"

# Build a combined search index from all tier 2 outputs
cat "$FILES_DIR"/*.md > /tmp/power-mapper-all-analyses.txt 2>/dev/null || true

# Check each inventoried file appears in at least one analysis
while IFS=$'\t' read -r _lines filepath; do
  # Strip leading ./ for matching (agents may use paths without ./ prefix)
  stripped="${filepath#./}"
  if grep -qF "$stripped" /tmp/power-mapper-all-analyses.txt 2>/dev/null; then
    ANALYZED=$((ANALYZED + 1))
  else
    MISSED=$((MISSED + 1))
    echo "$filepath" >> "$AUDIT_DIR/missed_files.txt"
  fi
done < "$INV_DIR/all_files.tsv"

# Clean up
rm -f /tmp/power-mapper-all-analyses.txt

# Calculate coverage
if [[ $TOTAL_FILES -gt 0 ]]; then
  COVERAGE=$(awk "BEGIN { printf \"%.1f\", ($ANALYZED / $TOTAL_FILES) * 100 }")
else
  COVERAGE="0.0"
fi

# Check Tier 3 domain coverage
DOMAIN_COUNT=$(wc -l < "$INV_DIR/domain_summary.tsv" | tr -d ' ')
DOMAIN_FILES=$(ls "$AUDIT_DIR/domains/"*.md 2>/dev/null | wc -l | tr -d ' ')

# Check Tier 4 thematic reports
THEME_FILES=$(ls "$AUDIT_DIR/themes/"*.md 2>/dev/null | wc -l | tr -d ' ')

# Check Tier 5 deliverables
FEATURES_EXISTS="no"; [[ -f "$AUDIT_DIR/FEATURES.md" ]] && FEATURES_EXISTS="yes"
GAPS_EXISTS="no"; [[ -f "$AUDIT_DIR/GAPS.md" ]] && GAPS_EXISTS="yes"
SUMMARY_EXISTS="no"; [[ -f "$AUDIT_DIR/AUDIT-SUMMARY.md" ]] && SUMMARY_EXISTS="yes"

# Write coverage report
cat > "$AUDIT_DIR/COVERAGE.txt" << EOF
=== COVERAGE REPORT ===
files_inventoried=$TOTAL_FILES
files_analyzed=$ANALYZED
files_missed=$MISSED
coverage_percent=$COVERAGE

tier2_chunks=$(ls "$FILES_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')
tier3_domains=$DOMAIN_FILES
tier3_domains_expected=$DOMAIN_COUNT
tier4_themes=$THEME_FILES
tier5_features=$FEATURES_EXISTS
tier5_gaps=$GAPS_EXISTS
tier5_summary=$SUMMARY_EXISTS
EOF

# Print results
echo ""
echo "=== COVERAGE REPORT ==="
echo ""
echo "Tier 2 (File Analysis):"
echo "  Files in inventory:  $TOTAL_FILES"
echo "  Files analyzed:      $ANALYZED"
echo "  Files missed:        $MISSED"
echo "  Coverage:            ${COVERAGE}%"
echo ""
echo "Tier 3 (Domain Synthesis):"
echo "  Domain summaries:    $DOMAIN_FILES"
echo ""
echo "Tier 4 (Thematic Reports):"
echo "  Theme reports:       $THEME_FILES"
echo ""
echo "Tier 5 (Deliverables):"
echo "  FEATURES.md:         $FEATURES_EXISTS"
echo "  GAPS.md:             $GAPS_EXISTS"
echo "  AUDIT-SUMMARY.md:    $SUMMARY_EXISTS"

if [[ $MISSED -gt 0 ]]; then
  echo ""
  echo "=== MISSED FILES ($MISSED) ==="
  head -20 "$AUDIT_DIR/missed_files.txt"
  if [[ $MISSED -gt 20 ]]; then
    echo "... and $((MISSED - 20)) more (see $AUDIT_DIR/missed_files.txt)"
  fi
  echo ""
  echo "ACTION: Create a new chunk with missed files and re-run Tier 2."
fi

echo ""
echo "Report: $AUDIT_DIR/COVERAGE.txt"
