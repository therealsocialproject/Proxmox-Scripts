#!/usr/bin/env bash
# ============================================================
#  io_speed_test.sh — Disk I/O benchmark for Ubuntu / Debian
#  Works on bare-metal VMs and containers (Docker, LXC, etc.)
#
#  Usage: sudo bash io_speed_test.sh [test_dir]
#
#  Auto-detects environment and adjusts:
#    - Skips O_DIRECT on overlayfs (Docker writable layer)
#    - Skips drop_caches if /proc/sys is not writable
#    - Falls back from libaio → sync engine if needed
#    - Warns when running unprivileged
# ============================================================

set -uo pipefail   # no -e so individual test failures don't abort the run

TEST_DIR="${1:-/tmp/io_test}"
RESULT_FILE="io_results_$(hostname)_$(date +%Y%m%d_%H%M%S).txt"
TEST_FILE="$TEST_DIR/io_testfile"
FILE_SIZE="1G"
FIO_SIZE="512M"
RUNTIME=30

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'
CYN='\033[0;36m'; BLD='\033[1m'; RST='\033[0m'

log()    { echo -e "${CYN}[INFO]${RST}  $*" | tee -a "$RESULT_FILE"; }
header() { echo -e "\n${BLD}${YLW}==============================${RST}" | tee -a "$RESULT_FILE"
           echo -e "${BLD}${YLW}  $*${RST}" | tee -a "$RESULT_FILE"
           echo -e "${BLD}${YLW}==============================${RST}" | tee -a "$RESULT_FILE"; }
result() { echo -e "${GRN}  ➜  $*${RST}" | tee -a "$RESULT_FILE"; }
warn()   { echo -e "${RED}[WARN]${RST}  $*" | tee -a "$RESULT_FILE"; }
info()   { echo -e "        $*" | tee -a "$RESULT_FILE"; }

# ══════════════════════════════════════════════════════════
# Environment detection
# ══════════════════════════════════════════════════════════
detect_env() {
  IS_CONTAINER=false
  IS_PRIVILEGED=false
  SUPPORTS_DIRECT_IO=true
  SUPPORTS_DROP_CACHE=false
  SUPPORTS_LIBAIO=true
  FS_TYPE="unknown"
  ENV_TYPE="VM / bare-metal"

  # Container detection — check multiple signals
  if [[ -f /.dockerenv ]] \
    || grep -qE '(docker|lxc|containerd|podman)' /proc/1/cgroup 2>/dev/null \
    || grep -qz 'container=' /proc/1/environ 2>/dev/null \
    || { command -v systemd-detect-virt &>/dev/null \
         && systemd-detect-virt --container &>/dev/null; }; then
    IS_CONTAINER=true
    ENV_TYPE="container"
  fi

  # Filesystem type for TEST_DIR mount point
  mkdir -p "$TEST_DIR"
  FS_TYPE=$(stat -f -c '%T' "$TEST_DIR" 2>/dev/null || echo "unknown")

  # overlayfs and tmpfs don't support O_DIRECT
  if [[ "$FS_TYPE" == "overlayfs" || "$FS_TYPE" == "overlay" || "$FS_TYPE" == "tmpfs" ]]; then
    SUPPORTS_DIRECT_IO=false
  fi

  # Probe O_DIRECT explicitly (catches FUSE, ZFS, NFS edge cases)
  if $SUPPORTS_DIRECT_IO; then
    if ! dd if=/dev/zero of="$TEST_DIR/.direct_probe" bs=4k count=1 oflag=direct 2>/dev/null; then
      SUPPORTS_DIRECT_IO=false
    fi
    rm -f "$TEST_DIR/.direct_probe"
  fi

  # Root check
  if [[ $EUID -eq 0 ]]; then
    IS_PRIVILEGED=true
  fi

  # drop_caches needs root AND a writable /proc/sys (not available in unprivileged containers)
  if $IS_PRIVILEGED && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null; then
    SUPPORTS_DROP_CACHE=true
  fi

  # libaio availability (not always present in minimal container images)
  if ! fio --name=probe --size=4k --rw=read --ioengine=libaio \
       --directory="$TEST_DIR" --bs=4k --iodepth=1 \
       --filename="$TEST_DIR/.libaio_probe" --output=/dev/null 2>/dev/null; then
    SUPPORTS_LIBAIO=false
  fi
  rm -f "$TEST_DIR/.libaio_probe"
}

# ══════════════════════════════════════════════════════════
# fio wrapper — applies correct engine + direct flag
# ══════════════════════════════════════════════════════════
run_fio() {
  local engine direct
  engine=$( $SUPPORTS_LIBAIO && echo "libaio" || echo "sync" )
  direct=$( $SUPPORTS_DIRECT_IO && echo "1"   || echo "0"   )
  fio --ioengine="$engine" --direct="$direct" "$@" 2>&1
}

# ══════════════════════════════════════════════════════════
# Preflight
# ══════════════════════════════════════════════════════════
mkdir -p "$TEST_DIR"
detect_env

echo -e "${BLD}IO Speed Test${RST} — $(date)" | tee "$RESULT_FILE"
echo "Host        : $(hostname)"                                              | tee -a "$RESULT_FILE"
echo "Kernel      : $(uname -r)"                                              | tee -a "$RESULT_FILE"
echo "Environment : $ENV_TYPE"                                                | tee -a "$RESULT_FILE"
echo "Test dir    : $TEST_DIR  (fs: $FS_TYPE)"                               | tee -a "$RESULT_FILE"
echo "Direct I/O  : $SUPPORTS_DIRECT_IO"                                     | tee -a "$RESULT_FILE"
echo "Drop caches : $SUPPORTS_DROP_CACHE"                                    | tee -a "$RESULT_FILE"
echo "IO engine   : $( $SUPPORTS_LIBAIO && echo "libaio" || echo "sync" )"  | tee -a "$RESULT_FILE"
echo "Output      : $RESULT_FILE"                                             | tee -a "$RESULT_FILE"

if ! $IS_PRIVILEGED; then
  warn "Not running as root — cache drop disabled. Read results may be inflated by page cache."
fi

if $IS_CONTAINER && ! $SUPPORTS_DIRECT_IO; then
  warn "overlayfs/tmpfs detected — O_DIRECT disabled. Testing container storage layer."
  info "Tip: pass a volume/bind-mount path to test underlying storage:"
  info "     sudo bash io_speed_test.sh /mnt/your-volume"
fi

FREE_KB=$(df -k "$TEST_DIR" | awk 'NR==2{print $4}')
if [[ $FREE_KB -lt 2097152 ]]; then
  warn "Less than 2 GB free on $TEST_DIR — consider freeing space for reliable results."
fi

# Install fio if missing
if ! command -v fio &>/dev/null; then
  log "fio not found — installing via apt…"
  apt-get update -qq && apt-get install -y -qq fio
fi

cleanup() { rm -f "$TEST_FILE" "$TEST_DIR"/fio_* "$TEST_DIR"/.*.probe 2>/dev/null; }
trap cleanup EXIT

# ══════════════════════════════════════════════════════════
# 1. DD — Sequential Write
# ══════════════════════════════════════════════════════════
header "1 · Sequential Write  (dd, $FILE_SIZE, fsync)"
log "Source: /dev/zero (avoids urandom CPU bottleneck)…"
DD_WRITE=$(dd if=/dev/zero of="$TEST_FILE" bs=1M count=1024 conv=fsync 2>&1 | tail -1)
result "$DD_WRITE"

# ══════════════════════════════════════════════════════════
# 2. DD — Sequential Read
# ══════════════════════════════════════════════════════════
header "2 · Sequential Read   (dd, $FILE_SIZE)"
if $SUPPORTS_DROP_CACHE; then
  log "Dropping page cache…"
  sync && echo 3 > /proc/sys/vm/drop_caches
else
  warn "Page cache not dropped — read speed may reflect RAM, not disk."
fi

if $SUPPORTS_DIRECT_IO; then
  DD_READ=$(dd if="$TEST_FILE" of=/dev/null bs=1M iflag=direct 2>&1 | tail -1)
  info "(O_DIRECT — bypasses page cache)"
else
  DD_READ=$(dd if="$TEST_FILE" of=/dev/null bs=1M 2>&1 | tail -1)
  info "(buffered — O_DIRECT not supported on $FS_TYPE)"
fi
result "$DD_READ"
rm -f "$TEST_FILE"

# ══════════════════════════════════════════════════════════
# 3. FIO — Sequential R/W
# ══════════════════════════════════════════════════════════
header "3 · Sequential R/W    (fio, 128K blocks, queue=32)"
run_fio \
  --name=seq_rw \
  --directory="$TEST_DIR" \
  --size="$FIO_SIZE" \
  --rw=rw \
  --bs=128k \
  --iodepth=32 \
  --numjobs=1 \
  --runtime=$RUNTIME \
  --time_based \
  --group_reporting \
  --output-format=normal \
  | grep -E "(READ|WRITE|iops|bw)" | tee -a "$RESULT_FILE"

# ══════════════════════════════════════════════════════════
# 4. FIO — Random Read IOPS
# ══════════════════════════════════════════════════════════
header "4 · Random Read IOPS  (fio, 4K blocks, queue=64)"
run_fio \
  --name=rand_read \
  --directory="$TEST_DIR" \
  --size="$FIO_SIZE" \
  --rw=randread \
  --bs=4k \
  --iodepth=64 \
  --numjobs=4 \
  --runtime=$RUNTIME \
  --time_based \
  --group_reporting \
  --output-format=normal \
  | grep -E "(READ|iops|bw)" | tee -a "$RESULT_FILE"

# ══════════════════════════════════════════════════════════
# 5. FIO — Random Write IOPS
# ══════════════════════════════════════════════════════════
header "5 · Random Write IOPS (fio, 4K blocks, queue=64)"
run_fio \
  --name=rand_write \
  --directory="$TEST_DIR" \
  --size="$FIO_SIZE" \
  --rw=randwrite \
  --bs=4k \
  --iodepth=64 \
  --numjobs=4 \
  --runtime=$RUNTIME \
  --time_based \
  --group_reporting \
  --output-format=normal \
  | grep -E "(WRITE|iops|bw)" | tee -a "$RESULT_FILE"

# ══════════════════════════════════════════════════════════
# 6. FIO — Mixed 70/30 R/W
# ══════════════════════════════════════════════════════════
header "6 · Mixed 70/30 R/W   (fio, 4K, queue=32)"
run_fio \
  --name=mixed \
  --directory="$TEST_DIR" \
  --size="$FIO_SIZE" \
  --rw=randrw \
  --rwmixread=70 \
  --bs=4k \
  --iodepth=32 \
  --numjobs=4 \
  --runtime=$RUNTIME \
  --time_based \
  --group_reporting \
  --output-format=normal \
  | grep -E "(READ|WRITE|iops|bw)" | tee -a "$RESULT_FILE"

# ══════════════════════════════════════════════════════════
# 7. Write Latency
# Always uses sync engine regardless of environment —
# measures true per-op fsync cost, not queue throughput.
# ══════════════════════════════════════════════════════════
header "7 · Write Latency     (fio, 4K, sync/fsync, queue=1)"
fio --name=latency \
  --directory="$TEST_DIR" \
  --size=256M \
  --rw=randwrite \
  --bs=4k \
  --iodepth=1 \
  --numjobs=1 \
  --ioengine=sync \
  --fsync=1 \
  --direct=0 \
  --runtime=$RUNTIME \
  --time_based \
  --group_reporting \
  --output-format=normal \
  2>&1 | grep -E "(WRITE|lat|iops)" | tee -a "$RESULT_FILE"

# ══════════════════════════════════════════════════════════
# Done
# ══════════════════════════════════════════════════════════
echo -e "\n${BLD}${GRN}All tests complete.${RST}" | tee -a "$RESULT_FILE"
echo -e "Results saved to: ${BLD}$RESULT_FILE${RST}"
