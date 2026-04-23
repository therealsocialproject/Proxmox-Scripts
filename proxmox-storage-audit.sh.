#!/usr/bin/env bash
set -euo pipefail

# proxmox-storage-audit.sh
#
# Audit Proxmox-managed storage volumes across all storages visible to `pvesm`.
#
# Features:
# - Enumerates all storages from `pvesm status`
# - Lists volumes from each storage using `pvesm list`
# - Classifies volumes as:
#     IN_USE
#     LIKELY_ORPHAN
#     AMBIGUOUS
#     SPECIAL_SKIP
# - Hides in-use volumes by default
# - Can optionally delete likely orphaned volumes using `pvesm free`
#
# Safety model:
# - Default mode is read-only reporting
# - Deletion only happens with --delete-orphans
# - Batch deletion only happens with both --delete-orphans and --yes
#
# Intended environment:
# - Proxmox VE host
# - Run as root
#
# Recommended first run:
#   ./proxmox-storage-audit.sh --dry-run
#
# Optional:
#   ./proxmox-storage-audit.sh --show-in-use --show-special --dry-run
#   ./proxmox-storage-audit.sh --delete-orphans
#   ./proxmox-storage-audit.sh --delete-orphans --yes

DRY_RUN=0
SHOW_IN_USE=0
SHOW_SPECIAL=0
DELETE_ORPHANS=0
YES=0
OUTPUT_CSV=""
QUIET=0

usage() {
  cat <<'EOF'
Usage:
  proxmox-storage-audit.sh [options]

Options:
  --dry-run         Report only, do not delete anything
  --show-in-use     Include volumes classified as IN_USE
  --show-special    Include volumes classified as SPECIAL_SKIP
  --delete-orphans  Prompt to delete LIKELY_ORPHAN volumes
  --yes             With --delete-orphans, delete all LIKELY_ORPHAN volumes without prompting
  --csv PATH        Write results to CSV file
  --quiet           Reduce non-essential output
  -h, --help        Show this help message

Examples:
  ./proxmox-storage-audit.sh --dry-run
  ./proxmox-storage-audit.sh --show-in-use --show-special --dry-run
  ./proxmox-storage-audit.sh --delete-orphans
  ./proxmox-storage-audit.sh --delete-orphans --yes
  ./proxmox-storage-audit.sh --dry-run --csv report.csv
EOF
}

log() {
  if [[ $QUIET -eq 0 ]]; then
    echo "$@"
  fi
}

warn() {
  echo "WARN: $*" >&2
}

err() {
  echo "ERROR: $*" >&2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "required command not found: $1"
    exit 1
  }
}

confirm() {
  local prompt="$1"
  local reply
  read -r -p "$prompt [y/N]: " reply || true
  [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
}

delete_volume() {
  local volid="$1"

  if [[ $DRY_RUN -eq 1 ]]; then
    echo "DRY-RUN: would delete $volid"
    return 0
  fi

  echo "Deleting: $volid"
  pvesm free "$volid"
}

csv_escape() {
  local s="$1"
  s="${s//\"/\"\"}"
  printf '"%s"' "$s"
}

print_item() {
  local storage="$1"
  local volid="$2"
  local format="$3"
  local vtype="$4"
  local size="$5"
  local vmid="$6"
  local class="$7"
  local reason="$8"

  echo "Storage : $storage"
  echo "Volume  : $volid"
  echo "Format  : ${format:-unknown}"
  echo "Type    : ${vtype:-unknown}"
  echo "Size    : ${size:-unknown}"
  echo "VMID    : ${vmid:-unknown}"
  echo "Class   : $class"
  echo "Reason  : $reason"
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --show-in-use) SHOW_IN_USE=1 ;;
    --show-special) SHOW_SPECIAL=1 ;;
    --delete-orphans) DELETE_ORPHANS=1 ;;
    --yes) YES=1 ;;
    --quiet) QUIET=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    --csv)
      err "--csv requires a path argument"
      exit 1
      ;;
    --csv=*)
      OUTPUT_CSV="${arg#*=}"
      ;;
    *)
      if [[ -z "$OUTPUT_CSV" && "${prev_arg:-}" == "--csv" ]]; then
        OUTPUT_CSV="$arg"
      else
        err "unknown option: $arg"
        usage
        exit 1
      fi
      ;;
  esac
  prev_arg="$arg"
done

for cmd in pvesm qm pct awk grep sort; do
  require_cmd "$cmd"
done

if [[ $EUID -ne 0 ]]; then
  err "run as root"
  exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

VMCFG="$TMPDIR/vm_configs.txt"
CTCFG="$TMPDIR/ct_configs.txt"

: > "$VMCFG"
: > "$CTCFG"

log "Collecting VM configuration references..."
while read -r vmid; do
  [[ -z "$vmid" ]] && continue
  {
    echo "### VMID $vmid ###"
    qm config "$vmid" 2>/dev/null || true
    echo
  } >> "$VMCFG"
done < <(qm list 2>/dev/null | awk 'NR>1 {print $1}')

log "Collecting container configuration references..."
while read -r ctid; do
  [[ -z "$ctid" ]] && continue
  {
    echo "### CTID $ctid ###"
    pct config "$ctid" 2>/dev/null || true
    echo
  } >> "$CTCFG"
done < <(pct list 2>/dev/null | awk 'NR>1 {print $1}')

find_reference() {
  local volid="$1"
  local short="${volid#*:}"

  local vmref=""
  local ctref=""

  vmref="$(grep -F "$volid" "$VMCFG" || true)"
  ctref="$(grep -F "$volid" "$CTCFG" || true)"

  if [[ -z "$vmref" && -z "$ctref" && -n "$short" ]]; then
    vmref="$(grep -F "$short" "$VMCFG" || true)"
    ctref="$(grep -F "$short" "$CTCFG" || true)"
  fi

  if [[ -n "$vmref" || -n "$ctref" ]]; then
    echo "yes"
  else
    echo "no"
  fi
}

vm_exists() {
  local vmid="$1"
  qm config "$vmid" >/dev/null 2>&1
}

ct_exists() {
  local ctid="$1"
  pct config "$ctid" >/dev/null 2>&1
}

classify_volume() {
  local volid="$1"
  local format="$2"
  local vtype="$3"
  local vmid="$4"

  local short="${volid#*:}"
  local has_ref
  has_ref="$(find_reference "$volid")"

  if [[ "$has_ref" == "yes" ]]; then
    echo "IN_USE|Referenced by current VM or container configuration"
    return
  fi

  # Cloud-init images are often safe only when their VM is definitely gone.
  if [[ "$short" == *cloudinit* ]]; then
    if [[ -n "${vmid:-}" && "$vmid" != "0" ]]; then
      if vm_exists "$vmid"; then
        echo "SPECIAL_SKIP|Cloud-init volume for existing VM $vmid"
      else
        echo "LIKELY_ORPHAN|Cloud-init volume for missing VM $vmid"
      fi
    else
      echo "SPECIAL_SKIP|Cloud-init volume"
    fi
    return
  fi

  # Saved state / state-like artifacts should be reviewed manually.
  if [[ "$short" == *state-* ]]; then
    echo "SPECIAL_SKIP|State or snapshot-related volume"
    return
  fi

  # Base volumes are often tied to templates or clones.
  if [[ "$short" == basevol-* ]]; then
    echo "SPECIAL_SKIP|Base volume or template-related volume"
    return
  fi

  # Container subvolumes/rootdirs
  if [[ "$format" == "subvol" || "$vtype" == "rootdir" ]]; then
    if [[ "$short" =~ ^subvol-([0-9]+)- ]]; then
      local ctid="${BASH_REMATCH[1]}"
      if ct_exists "$ctid"; then
        echo "AMBIGUOUS|Container subvolume has no direct reference but container $ctid exists"
      else
        echo "LIKELY_ORPHAN|Container subvolume for missing container $ctid"
      fi
    else
      echo "SPECIAL_SKIP|Non-standard subvolume or rootdir"
    fi
    return
  fi

  # VM disks
  if [[ "$short" =~ ^vm-([0-9]+)- ]]; then
    local inferred_vmid="${BASH_REMATCH[1]}"
    if vm_exists "$inferred_vmid"; then
      echo "AMBIGUOUS|VM-style disk name matches existing VM $inferred_vmid but no config reference was found"
    else
      echo "LIKELY_ORPHAN|VM disk for missing VM $inferred_vmid"
    fi
    return
  fi

  echo "AMBIGUOUS|No active reference found, but naming pattern is non-standard"
}

declare -a IN_USE_ITEMS
declare -a ORPHAN_ITEMS
declare -a AMBIGUOUS_ITEMS
declare -a SPECIAL_ITEMS
declare -a ALL_ITEMS

log "Scanning Proxmox storages..."
mapfile -t STORAGES < <(pvesm status | awk 'NR>1 {print $1}' | sort -u)

for storage in "${STORAGES[@]}"; do
  [[ -z "$storage" ]] && continue

  if ! pvesm list "$storage" >/dev/null 2>&1; then
    warn "skipping storage '$storage' because it could not be listed"
    continue
  fi

  while IFS='|' read -r volid format vtype size vmid; do
    [[ -z "$volid" ]] && continue

    result="$(classify_volume "$volid" "$format" "$vtype" "$vmid")"
    class="${result%%|*}"
    reason="${result#*|}"

    record="${storage}|${volid}|${format}|${vtype}|${size}|${vmid}|${class}|${reason}"
    ALL_ITEMS+=("$record")

    case "$class" in
      IN_USE) IN_USE_ITEMS+=("$record") ;;
      LIKELY_ORPHAN) ORPHAN_ITEMS+=("$record") ;;
      AMBIGUOUS) AMBIGUOUS_ITEMS+=("$record") ;;
      SPECIAL_SKIP) SPECIAL_ITEMS+=("$record") ;;
      *) AMBIGUOUS_ITEMS+=("$record") ;;
    esac
  done < <(pvesm list "$storage" 2>/dev/null | awk 'NR>1 {print $1 "|" $2 "|" $3 "|" $4 "|" $5}')
done

if [[ -n "$OUTPUT_CSV" ]]; then
  {
    echo '"storage","volid","format","type","size","vmid","class","reason"'
    for rec in "${ALL_ITEMS[@]}"; do
      IFS='|' read -r storage volid format vtype size vmid class reason <<< "$rec"
      printf '%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$(csv_escape "$storage")" \
        "$(csv_escape "$volid")" \
        "$(csv_escape "$format")" \
        "$(csv_escape "$vtype")" \
        "$(csv_escape "$size")" \
        "$(csv_escape "$vmid")" \
        "$(csv_escape "$class")" \
        "$(csv_escape "$reason")"
    done
  } > "$OUTPUT_CSV"
  log "Wrote CSV report to: $OUTPUT_CSV"
fi

echo
echo "==================== Summary ===================="
echo "In use         : ${#IN_USE_ITEMS[@]}"
echo "Likely orphan  : ${#ORPHAN_ITEMS[@]}"
echo "Ambiguous      : ${#AMBIGUOUS_ITEMS[@]}"
echo "Special skip   : ${#SPECIAL_ITEMS[@]}"
echo "================================================="
echo

if [[ ${#ORPHAN_ITEMS[@]} -gt 0 ]]; then
  echo "========== Likely Orphaned Volumes =========="
  for rec in "${ORPHAN_ITEMS[@]}"; do
    IFS='|' read -r storage volid format vtype size vmid class reason <<< "$rec"
    print_item "$storage" "$volid" "$format" "$vtype" "$size" "$vmid" "$class" "$reason"
    echo
  done
fi

if [[ ${#AMBIGUOUS_ITEMS[@]} -gt 0 ]]; then
  echo "========== Ambiguous Volumes =========="
  for rec in "${AMBIGUOUS_ITEMS[@]}"; do
    IFS='|' read -r storage volid format vtype size vmid class reason <<< "$rec"
    print_item "$storage" "$volid" "$format" "$vtype" "$size" "$vmid" "$class" "$reason"
    echo
  done
fi

if [[ $SHOW_SPECIAL -eq 1 && ${#SPECIAL_ITEMS[@]} -gt 0 ]]; then
  echo "========== Special / Skipped Volumes =========="
  for rec in "${SPECIAL_ITEMS[@]}"; do
    IFS='|' read -r storage volid format vtype size vmid class reason <<< "$rec"
    print_item "$storage" "$volid" "$format" "$vtype" "$size" "$vmid" "$class" "$reason"
    echo
  done
fi

if [[ $SHOW_IN_USE -eq 1 && ${#IN_USE_ITEMS[@]} -gt 0 ]]; then
  echo "========== In-Use Volumes =========="
  for rec in "${IN_USE_ITEMS[@]}"; do
    IFS='|' read -r storage volid format vtype size vmid class reason <<< "$rec"
    print_item "$storage" "$volid" "$format" "$vtype" "$size" "$vmid" "$class" "$reason"
    echo
  done
fi

if [[ ${#ORPHAN_ITEMS[@]} -eq 0 ]]; then
  echo "No likely orphaned volumes found."
  exit 0
fi

if [[ $DELETE_ORPHANS -ne 1 ]]; then
  echo "Run with --delete-orphans to remove likely orphaned volumes."
  exit 0
fi

if [[ $YES -eq 1 ]]; then
  for rec in "${ORPHAN_ITEMS[@]}"; do
    IFS='|' read -r _ volid _ _ _ _ _ _ <<< "$rec"
    delete_volume "$volid"
  done
  exit 0
fi

for rec in "${ORPHAN_ITEMS[@]}"; do
  IFS='|' read -r storage volid format vtype size vmid class reason <<< "$rec"
  print_item "$storage" "$volid" "$format" "$vtype" "$size" "$vmid" "$class" "$reason"
  if confirm "Delete this likely orphaned volume?"; then
    delete_volume "$volid"
  fi
  echo
done
