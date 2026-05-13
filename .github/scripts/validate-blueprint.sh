#!/usr/bin/env bash
# Mechanical pre-QA gate for Aviatrix blueprints.
#
# Runs the portable subset of the .claude/skills/validate-blueprint skill:
# Tier 1 deployment blockers, Tier 2 repo standards, Tier 3 advisory warnings.
# Semantic checks (var satisfiability, README content quality, hardcoded-region
# detection) are intentionally left to the LLM-driven skill.
#
# Usage:
#   .github/scripts/validate-blueprint.sh <blueprint-dir> [--no-init]
#
# Exit codes:
#   0 - all Tier 1 + Tier 2 mechanical checks passed (Tier 3 may warn)
#   1 - one or more Tier 1 or Tier 2 checks failed
#   2 - usage error

set -uo pipefail

BP="${1:-}"
SKIP_INIT=0
[[ "${2:-}" == "--no-init" ]] && SKIP_INIT=1

if [[ -z "$BP" || ! -d "$BP" ]]; then
  echo "usage: $0 <blueprint-dir> [--no-init]" >&2
  exit 2
fi

BP="${BP%/}"
BP_NAME="$(basename "$BP")"
BP_ABS="$(cd "$BP" && pwd)"
REPO_ROOT="$(git -C "$BP_ABS" rev-parse --show-toplevel 2>/dev/null || echo "")"

T1_FAILS=()
T2_FAILS=()
T3_WARNS=()

t1_fail() { T1_FAILS+=("$1"); }
t2_fail() { T2_FAILS+=("$1"); }
t3_warn() { T3_WARNS+=("$1"); }

# --------------------------------------------------------------------
# Shape detection
# --------------------------------------------------------------------

CLOUD_DIRS=()
for cloud in aws azure gcp oci; do
  [[ -d "$BP_ABS/$cloud" ]] && CLOUD_DIRS+=("$cloud")
done

mapfile -t LEAVES < <(
  find "$BP_ABS" -type f -name '*.tf' \
    -not -path '*/.terraform/*' \
    -not -path '*/modules/*' \
    -exec dirname {} \; | sort -u
)

if [[ ${#LEAVES[@]} -eq 0 ]]; then
  echo "ERROR: no .tf leaves found under $BP_ABS" >&2
  exit 2
fi

if [[ ${#CLOUD_DIRS[@]} -gt 0 ]]; then
  SHAPE="multi-cloud × multi-layer"
elif [[ ${#LEAVES[@]} -eq 1 ]]; then
  SHAPE="single-layer"
else
  SHAPE="multi-layer"
fi

# --------------------------------------------------------------------
# Tier 1.1 / 1.2 — terraform init -backend=false + validate per leaf
# --------------------------------------------------------------------

run_init_validate() {
  local leaf="$1"
  local rel="${leaf#$BP_ABS/}"
  [[ "$rel" == "$leaf" ]] && rel="."

  rm -rf "$leaf/.terraform"
  if [[ -n "$REPO_ROOT" ]] && git -C "$REPO_ROOT" check-ignore -q "$leaf/.terraform.lock.hcl" 2>/dev/null; then
    rm -f "$leaf/.terraform.lock.hcl"
  fi

  local init_log validate_log
  init_log="$(cd "$leaf" && terraform init -backend=false -input=false -no-color 2>&1)"
  if [[ $? -ne 0 ]]; then
    local first_err
    first_err="$(echo "$init_log" | grep -m1 -E '^(Error|│ Error)' | sed 's/^│ //')"
    t1_fail "T1.1 init failed at $rel: ${first_err:-see CI log}"
    return
  fi

  validate_log="$(cd "$leaf" && terraform validate -no-color 2>&1)"
  if [[ $? -ne 0 ]]; then
    local first_err
    first_err="$(echo "$validate_log" | grep -m1 -E '^(Error|│ Error)' | sed 's/^│ //')"
    t1_fail "T1.2 validate failed at $rel: ${first_err:-see CI log}"
  fi
}

if [[ $SKIP_INIT -eq 0 ]]; then
  for leaf in "${LEAVES[@]}"; do
    run_init_validate "$leaf"
  done
fi

# --------------------------------------------------------------------
# Tier 1.3 — module source paths resolve
# --------------------------------------------------------------------

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  file="${line%%:*}"
  rest="${line#*:}"
  src="$(echo "$rest" | sed -nE 's/.*source[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p')"
  [[ -z "$src" ]] && continue
  case "$src" in
    ./*|../*) ;;
    *) continue ;;
  esac
  src_dir="$(cd "$(dirname "$file")" && cd "$src" 2>/dev/null && pwd)" || src_dir=""
  if [[ -z "$src_dir" || ! -d "$src_dir" ]]; then
    rel="${file#$BP_ABS/}"
    t1_fail "T1.3 unresolved module source in $rel: $src"
    continue
  fi
  if ! ls "$src_dir"/*.tf >/dev/null 2>&1; then
    rel="${file#$BP_ABS/}"
    t1_fail "T1.3 module dir has no .tf files in $rel: $src"
  fi
done < <(grep -rEn 'source[[:space:]]*=[[:space:]]*"\.{1,2}/' "$BP_ABS" --include='*.tf' 2>/dev/null || true)

# --------------------------------------------------------------------
# Tier 1.4 — terraform_remote_state references resolve, backend=local
# --------------------------------------------------------------------

while IFS= read -r tf_file; do
  rel="${tf_file#$BP_ABS/}"
  while IFS= read -r start_line; do
    [[ -z "$start_line" ]] && continue
    block="$(awk -v start="$start_line" '
      NR < start { next }
      NR == start { in_block=1 }
      in_block {
        print
        for (i=1; i<=length($0); i++) {
          c = substr($0, i, 1)
          if (c == "{") depth++
          else if (c == "}") { depth--; if (depth==0) exit }
        }
      }
    ' "$tf_file")"

    backend="$(echo "$block" | sed -nE 's/.*backend[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' | head -1)"
    pathv="$(echo "$block" | sed -nE 's/.*path[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' | head -1)"

    if [[ -n "$backend" && "$backend" != "local" ]]; then
      t1_fail "T1.4 non-local backend in $rel:$start_line (backend=\"$backend\")"
    fi
    if [[ -n "$pathv" ]]; then
      target_dir="$(cd "$(dirname "$tf_file")" 2>/dev/null && cd "$(dirname "$pathv")" 2>/dev/null && pwd)" || target_dir=""
      if [[ -z "$target_dir" || ! -d "$target_dir" ]]; then
        t1_fail "T1.4 remote_state path does not resolve in $rel:$start_line (path=\"$pathv\")"
      elif ! ls "$target_dir"/*.tf >/dev/null 2>&1; then
        t1_fail "T1.4 remote_state target dir has no .tf files in $rel:$start_line (path=\"$pathv\")"
      fi
    fi
  done < <(grep -nE 'data[[:space:]]+"terraform_remote_state"' "$tf_file" 2>/dev/null | cut -d: -f1)
done < <(grep -rl 'terraform_remote_state' "$BP_ABS" --include='*.tf' 2>/dev/null || true)

# --------------------------------------------------------------------
# Tier 1.6 — multi-cloud parity
# --------------------------------------------------------------------

if [[ ${#CLOUD_DIRS[@]} -ge 2 ]]; then
  declare -a CLOUD_LAYOUTS=()
  for c in "${CLOUD_DIRS[@]}"; do
    layout="$(cd "$BP_ABS/$c" && find . -type f -name '*.tf' \
      -not -path '*/.terraform/*' -not -path '*/modules/*' \
      -exec dirname {} \; 2>/dev/null | sort -u | tr '\n' ',')"
    CLOUD_LAYOUTS+=("$layout")
  done
  first="${CLOUD_LAYOUTS[0]}"
  for i in "${!CLOUD_DIRS[@]}"; do
    if [[ "${CLOUD_LAYOUTS[$i]}" != "$first" ]]; then
      t1_fail "T1.6 cloud subdir layout differs: ${CLOUD_DIRS[0]} vs ${CLOUD_DIRS[$i]}"
    fi
  done

  README="$BP_ABS/README.md"
  if [[ -f "$README" ]]; then
    for c in "${CLOUD_DIRS[@]}"; do
      if ! grep -qi -E "(^|[^a-z])${c}([^a-z]|$)" "$README"; then
        t1_fail "T1.6 cloud subdir '$c/' present but not mentioned in README.md"
      fi
    done
  fi
fi

# --------------------------------------------------------------------
# Tier 1.7 — plaintext credentials in committed example files
# --------------------------------------------------------------------

while IFS= read -r ex; do
  rel="${ex#$BP_ABS/}"
  while IFS= read -r m; do
    line_no="${m%%:*}"
    txt="${m#*:}"
    t1_fail "T1.7 plaintext cred in $rel:$line_no -> $(echo "$txt" | sed 's/^[[:space:]]*//')"
  done < <(grep -nE '^[[:space:]]*(aviatrix_password|aviatrix_username|aviatrix_controller_ip)[[:space:]]*=' "$ex" 2>/dev/null || true)

  while IFS= read -r m; do
    line_no="${m%%:*}"
    t1_fail "T1.7 AWS access key pattern in $rel:$line_no"
  done < <(grep -nE 'AKIA[0-9A-Z]{16}' "$ex" 2>/dev/null || true)

  while IFS= read -r m; do
    line_no="${m%%:*}"
    t1_fail "T1.7 PEM private key pattern in $rel:$line_no"
  done < <(grep -nE '-----BEGIN .* PRIVATE KEY-----' "$ex" 2>/dev/null || true)
done < <(find "$BP_ABS" -type f \( -name '*.tfvars.example' -o -name '*.tfvars' \) \
           -not -path '*/.terraform/*' 2>/dev/null || true)

# --------------------------------------------------------------------
# Tier 2.1 — required files per leaf
# --------------------------------------------------------------------

for leaf in "${LEAVES[@]}"; do
  rel="${leaf#$BP_ABS/}"
  [[ "$rel" == "$leaf" ]] && rel="."
  [[ -f "$leaf/main.tf" ]] || t2_fail "T2.1 missing main.tf in $rel"
  if ! grep -lE 'required_providers[[:space:]]*[={]' "$leaf"/*.tf >/dev/null 2>&1; then
    t2_fail "T2.1 no required_providers block (versions.tf or inline in any .tf) in $rel"
  fi
  if grep -lE '^[[:space:]]*variable[[:space:]]+"' "$leaf"/*.tf >/dev/null 2>&1; then
    [[ -f "$leaf/variables.tf" ]] || t2_fail "T2.1 variable blocks present but no variables.tf in $rel"
  fi
done

# --------------------------------------------------------------------
# Tier 2.3 — architecture diagram
# --------------------------------------------------------------------

if [[ ! -f "$BP_ABS/architecture.svg" && ! -f "$BP_ABS/architecture.png" ]]; then
  t2_fail "T2.3 missing architecture.svg or architecture.png at blueprint root"
fi

# --------------------------------------------------------------------
# Tier 2.4 — README required sections (header presence only)
# --------------------------------------------------------------------

README="$BP_ABS/README.md"
if [[ ! -f "$README" ]]; then
  t2_fail "T2.4 README.md missing at blueprint root"
else
  declare -a REQUIRED_SECTIONS=(
    "Architecture"
    "Prerequisites"
    "Deploy|Quickstart"
    "Troubleshooting"
    "Cleanup|Destroy|Teardown"
  )
  for sec in "${REQUIRED_SECTIONS[@]}"; do
    if ! grep -qiE "^#{1,4}[[:space:]]+.*($sec)" "$README"; then
      pretty="${sec//|/ or }"
      t2_fail "T2.4 README missing section: $pretty"
    fi
  done

  declare -a ADVISORY_SECTIONS=(
    "Resource(s| Inventory)"
    "Variable"
    "Output"
    "Test|Verif"
  )
  for sec in "${ADVISORY_SECTIONS[@]}"; do
    if ! grep -qiE "^#{1,4}[[:space:]]+.*($sec)" "$README"; then
      pretty="${sec//|/ or }"
      t3_warn "T3.x README has no section header for: $pretty"
    fi
  done
fi

# --------------------------------------------------------------------
# Tier 2.6 — blueprint dir name convention
# --------------------------------------------------------------------

if [[ ! "$BP_NAME" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  t2_fail "T2.6 blueprint dir name '$BP_NAME' is not lowercase-with-hyphens"
fi

# --------------------------------------------------------------------
# Tier 2.8 — .gitignore hygiene + no tracked tfstate/tfvars
# --------------------------------------------------------------------

if [[ -n "$REPO_ROOT" ]]; then
  pushd "$REPO_ROOT" >/dev/null
  rel_bp="${BP_ABS#$REPO_ROOT/}"
  while IFS= read -r tracked; do
    [[ -z "$tracked" ]] && continue
    case "$tracked" in
      *.tfvars.example) continue ;;
      *.tfvars|*.tfstate|*.tfstate.*)
        t2_fail "T2.8 tracked file should be gitignored: $tracked"
        ;;
    esac
  done < <(git ls-files "$rel_bp" 2>/dev/null | grep -E '(\.tfstate$|\.tfstate\.|\.tfvars$|\.tfvars\.[^e])' || true)
  popd >/dev/null
fi

# --------------------------------------------------------------------
# Tier 3 — advisory warnings
# --------------------------------------------------------------------

if [[ -f "$README" ]]; then
  lines="$(wc -l < "$README" | tr -d ' ')"
  if [[ "$lines" -lt 300 && ${#LEAVES[@]} -gt 1 ]]; then
    t3_warn "T3.1 README is thin ($lines lines) for a multi-layer blueprint"
  fi
  grep -qiE '(\$|USD|cost|hourly|monthly)' "$README" || t3_warn "T3.2 README has no cost/pricing language"
  grep -qiE '(tested[ -]with|tested versions|version[[:space:]]+table)' "$README" || t3_warn "T3.3 README has no Tested-With table/section"
fi

# --------------------------------------------------------------------
# Report
# --------------------------------------------------------------------

verdict_emoji="✅"
verdict_text="READY FOR QA"
exit_code=0
if [[ ${#T1_FAILS[@]} -gt 0 ]]; then
  verdict_emoji="🚫"
  verdict_text="BLOCKED — do not submit to QA"
  exit_code=1
elif [[ ${#T2_FAILS[@]} -gt 0 ]]; then
  verdict_emoji="⚠️"
  verdict_text="NEEDS WORK — repo standards violations"
  exit_code=1
fi

print_section() {
  local title="$1"; shift
  local -a items=("$@")
  echo
  echo "$title"
  if [[ ${#items[@]} -eq 0 ]]; then
    echo "  (none)"
  else
    for it in "${items[@]}"; do
      echo "  - $it"
    done
  fi
}

{
  echo "Blueprint: $BP_NAME"
  echo "Path: $BP_ABS"
  echo "Shape: $SHAPE"
  echo "Leaves: ${#LEAVES[@]}"
  for leaf in "${LEAVES[@]}"; do
    rel="${leaf#$BP_ABS/}"; [[ "$rel" == "$leaf" ]] && rel="."
    echo "  - $rel"
  done
  echo
  echo "═══════════════════════════════════════════════════"
  echo "VERDICT: $verdict_emoji $verdict_text"
  echo "═══════════════════════════════════════════════════"
  print_section "Tier 1 — Deployment Blockers" "${T1_FAILS[@]+"${T1_FAILS[@]}"}"
  print_section "Tier 2 — Repository Standards" "${T2_FAILS[@]+"${T2_FAILS[@]}"}"
  print_section "Tier 3 — Quality (advisory)" "${T3_WARNS[@]+"${T3_WARNS[@]}"}"
  echo
  echo "═══════════════════════════════════════════════════"
  echo "VERDICT: $verdict_emoji $verdict_text"
  echo "═══════════════════════════════════════════════════"
} | tee /dev/null

# GitHub Actions step summary
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## $verdict_emoji \`$BP_NAME\` — $verdict_text"
    echo ""
    echo "**Shape:** $SHAPE  •  **Leaves:** ${#LEAVES[@]}"
    echo ""
    if [[ ${#T1_FAILS[@]} -gt 0 ]]; then
      echo "### Tier 1 — Deployment Blockers"
      for it in "${T1_FAILS[@]}"; do echo "- $it"; done
      echo ""
    fi
    if [[ ${#T2_FAILS[@]} -gt 0 ]]; then
      echo "### Tier 2 — Repository Standards"
      for it in "${T2_FAILS[@]}"; do echo "- $it"; done
      echo ""
    fi
    if [[ ${#T3_WARNS[@]} -gt 0 ]]; then
      echo "<details><summary>Tier 3 — Advisory (${#T3_WARNS[@]})</summary>"
      echo ""
      for it in "${T3_WARNS[@]}"; do echo "- $it"; done
      echo ""
      echo "</details>"
    fi
  } >> "$GITHUB_STEP_SUMMARY"
fi

exit $exit_code
