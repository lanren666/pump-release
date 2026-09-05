#!/usr/bin/env bash
# Dev launcher: clean leftover iOS debug tunnels, then flutter run/attach
# with a timestamped console log under .debug_logs/.
#
# Why a clean start is required:
# - Ctrl+C does not kill SporraMom on the phone. A leftover Runner makes the
#   next flutter run hang at "Installing and launching" / Dart VM Service.
# - Stale iproxy/idevicesyslog (sometimes days old) occupy usbmux port 51904.
# - all_proxy=socks5://... hijacks localhost VM discovery; keep http(s)_proxy
#   and only bypass local/LAN via NO_PROXY.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LOG_DIR="$ROOT/.debug_logs"
DEFAULT_IOS_UDID="${FLUTTER_DEVICE:-${IOS_UDID:-00008110-001124543486401E}}"

MODE="run"
DEVICE=""
KEEP_APP=0
CLEAN_HOST=1
VERBOSE=0
DO_PUB=0
EXTRA_ARGS=()

usage() {
  cat <<'EOF'
用法: ./scripts/start_dev.sh [选项] [-- flutter 额外参数]

  -d, --device ID   指定设备（默认：已连接的 iPhone，否则第一台 mobile）
  --attach          不重装，只把调试器挂到已经在跑的 App（更快）
  --keep-app        不结束手机上已在运行的 SporraMom
  --no-clean        不清理本机残留 iproxy / idevicesyslog / flutter run
  --pub             启动前跑 pub get（默认跳过，加快重复启动）
  --verbose         flutter --verbose
  -h, --help        显示帮助

日志每次写入 .debug_logs/dev_YYYYMMDD_HHMMSS.log，
并把路径记到 .debug_logs/latest_path.txt。

示例:
  ./scripts/start_dev.sh
  ./scripts/start_dev.sh --attach
  ./scripts/start_dev.sh -d 00008110-001124543486401E -- --dart-define=PUMP_LOG_LEVEL=debug
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -d|--device)
      DEVICE="${2:-}"
      if [[ -z "$DEVICE" ]]; then
        echo "缺少 --device 参数" >&2
        exit 2
      fi
      shift 2
      ;;
    --attach)
      MODE="attach"
      shift
      ;;
    --keep-app)
      KEEP_APP=1
      shift
      ;;
    --no-clean)
      CLEAN_HOST=0
      shift
      ;;
    --pub)
      DO_PUB=1
      shift
      ;;
    --verbose)
      VERBOSE=1
      shift
      ;;
    --)
      shift
      EXTRA_ARGS+=("$@")
      break
      ;;
    *)
      EXTRA_ARGS+=("$1")
      shift
      ;;
  esac
done

log() {
  printf '%s\n' "$*"
}

# Keep Clash/HTTP proxy for pub/pods, but never proxy Dart VM / USB forwards.
prepare_proxy() {
  unset all_proxy ALL_PROXY
  local extra_no="localhost,127.0.0.1,::1,.local"
  if [[ -n "${no_proxy:-}${NO_PROXY:-}" ]]; then
    export no_proxy="${no_proxy:-${NO_PROXY}},${extra_no}"
  else
    export no_proxy="$extra_no"
  fi
  export NO_PROXY="$no_proxy"
}

DEVICES_JSON=""

load_devices() {
  DEVICES_JSON="$(flutter devices --machine)"
}

device_platform() {
  local id="$1"
  python3 -c 'import json,sys
want=sys.argv[1]
for d in json.loads(sys.argv[2]):
    if d.get("id")==want:
        print(d.get("targetPlatform") or "")
        raise SystemExit
print("")
' "$id" "$DEVICES_JSON"
}

pick_device() {
  if [[ -n "$DEVICE" ]]; then
    return
  fi
  DEVICE="$(
    python3 -c 'import json,sys
prefer=sys.argv[1]
devices=json.loads(sys.argv[2])
ids=[d.get("id") for d in devices]
if prefer in ids:
    print(prefer)
    raise SystemExit
for d in devices:
    platform=d.get("targetPlatform") or ""
    if platform.startswith("ios") and d.get("id"):
        print(d["id"])
        raise SystemExit
for d in devices:
    platform=d.get("targetPlatform") or ""
    if platform.startswith("android") and d.get("id"):
        print(d["id"])
        raise SystemExit
print("")
' "$DEFAULT_IOS_UDID" "$DEVICES_JSON"
  )"
  if [[ -z "$DEVICE" ]]; then
    echo "没有找到可用的 iOS/Android 设备。先插上手机，或用 -d 指定。" >&2
    flutter devices >&2 || true
    exit 1
  fi
}

kill_matching() {
  local pattern="${1:-}"
  local pids
  if [[ -z "$pattern" ]]; then
    return
  fi
  # Exclude this launcher so pgrep -f cannot kill start_dev.sh itself.
  pids="$(pgrep -f "$pattern" | awk -v self="$$" '$1 != self {print}' || true)"
  if [[ -z "$pids" ]]; then
    return
  fi
  log "结束残留进程: $pattern"
  # shellcheck disable=SC2086
  kill $pids 2>/dev/null || true
  sleep 0.4
  pids="$(pgrep -f "$pattern" | awk -v self="$$" '$1 != self {print}' || true)"
  if [[ -n "$pids" ]]; then
    # shellcheck disable=SC2086
    kill -9 $pids 2>/dev/null || true
  fi
}

cleanup_host() {
  local device_id="${1:-}"
  if [[ -z "$device_id" ]]; then
    log "跳过本机清理：设备 ID 为空"
    return
  fi
  log "清理本机调试残留: device=${device_id}"
  kill_matching "iproxy .*${device_id}"
  kill_matching "idevicesyslog -u ${device_id}"
  kill_matching "flutter_tools.snapshot run -d ${device_id}"
  kill_matching "flutter_tools.snapshot attach -d ${device_id}"
}

stop_ios_app() {
  local device_id="${1:-}"
  if [[ -z "$device_id" ]]; then
    return
  fi
  if ! command -v xcrun >/dev/null 2>&1; then
    return
  fi
  local json
  json="$(mktemp)"
  if ! xcrun devicectl device info processes \
      --device "$device_id" \
      --json-output "$json" \
      --quiet \
      --timeout 20 >/dev/null 2>&1; then
    rm -f "$json"
    log "无法列出手机进程（可能锁屏或未信任），跳过结束 App。"
    return
  fi
  local pids
  pids="$(
    python3 - "$json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
result = data.get("result") or {}
procs = result.get("runningProcesses") or result.get("processes") or []
if not procs:
    for value in result.values():
        if isinstance(value, list):
            procs = value
            break
pids = []
for proc in procs:
    exe = str(proc.get("executable") or "")
    if "/Runner.app/Runner" in exe and "/PlugIns/" not in exe:
        pid = proc.get("processIdentifier")
        if pid is not None:
            pids.append(str(pid))
print(" ".join(pids))
PY
  )"
  rm -f "$json"
  if [[ -z "$pids" ]]; then
    log "手机上没有残留的 Runner。"
    return
  fi
  log "结束手机上残留的 Runner pid=${pids}，避免 FlutterEngine already invoked。"
  local pid
  for pid in $pids; do
    xcrun devicectl device process terminate \
      --device "$device_id" \
      --pid "$pid" \
      --kill \
      --quiet \
      --timeout 10 >/dev/null 2>&1 || true
  done
}

prepare_proxy
load_devices
pick_device
PLATFORM="$(device_platform "$DEVICE")"
STAMP="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/dev_${STAMP}.log"
printf '%s\n' "$LOG_FILE" > "$LOG_DIR/latest_path.txt"

log "设备: $DEVICE  ($PLATFORM)"
log "日志: $LOG_FILE"

if [[ "$CLEAN_HOST" -eq 1 ]]; then
  cleanup_host "$DEVICE"
fi

if [[ "$KEEP_APP" -eq 0 && "$MODE" == "run" && "$PLATFORM" == ios* ]]; then
  stop_ios_app "$DEVICE"
fi

FLUTTER_ARGS=()
if [[ "$VERBOSE" -eq 1 ]]; then
  FLUTTER_ARGS+=(--verbose)
fi
FLUTTER_ARGS+=(-d "$DEVICE")
# --no-pub / --dart-define are flutter run flags; attach rejects them.
if [[ "$MODE" == "run" ]]; then
  if [[ "$DO_PUB" -eq 0 ]]; then
    FLUTTER_ARGS+=(--no-pub)
  fi
  FLUTTER_ARGS+=(--dart-define=INTERNAL_DIAGNOSTICS=true)
fi
if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
  FLUTTER_ARGS+=("${EXTRA_ARGS[@]}")
fi

{
  echo "===== start_dev $(date '+%Y-%m-%d %H:%M:%S %z') ====="
  echo "mode=$MODE device=$DEVICE platform=$PLATFORM"
  echo "proxy http=${http_proxy:-} https=${https_proxy:-} all=${all_proxy:-}"
  echo "NO_PROXY=$NO_PROXY"
  echo "cwd=$ROOT"
  echo "args=${FLUTTER_ARGS[*]}"
  echo "===================================================="
} | tee "$LOG_FILE" >/dev/null

log "开始 ${MODE}. 编辑器打开的 log 不会自动刷新，请用: tail -f ${LOG_FILE}"
log "日常改 Dart 时不要反复完整启动，热重载即可；下次要挂回已运行的 App 用 --attach."

# script gives Flutter a TTY so debugPrint keeps streaming; -F flushes the log.
run_flutter() {
  script -aeFq "$LOG_FILE" "$@"
}

if [[ "$MODE" == "attach" ]]; then
  log "attach 只记录连上之后的新日志，不会回放 attach 之前的 flutter: 输出。"
  log "若报 Error connecting，改跑 ./scripts/start_dev.sh"
  run_flutter flutter attach --app-id com.sporramom.pump "${FLUTTER_ARGS[@]}"
  exit "$?"
fi

run_flutter flutter run "${FLUTTER_ARGS[@]}"
exit "$?"
