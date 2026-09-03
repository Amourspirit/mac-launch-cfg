#!/usr/bin/env zsh
# mac-launch-cfg.zsh
#
# Move `user1`-only LaunchAgents/LaunchDaemons out of the system-wide
# /Library location (where they auto-start for every user session)
# and into `user1`'s per-user ~/Library location so they only load
# when `user1` logs in.
#
# Default action  : apply (copy -> chown -> disable original)
# --undo          : reverse (restore original names, remove copies)
# --redo          : alias for apply (explicit re-application)
# --dry-run       : print what would happen, do nothing
# -h | --help     : usage
#
# Requires: sudo (writes to /Library and chown on copies).

set -u
setopt ERR_EXIT PIPE_FAIL

# ---- Config ----------------------------------------------------------------

detect_el_user() {
  # Resolve the target user, in priority order:
  #   1. $EL_USER already set in environment (explicit override)
  #   2. $SUDO_USER (set when invoked via sudo)
  #   3. GUI console owner on macOS (stat -f %Su /dev/console)
  #   4. logname (controlling terminal's login name)
  #   5. $USER / whoami as last resort
  local u=""
  if [[ -n "${EL_USER:-}" ]]; then
    print -r -- "$EL_USER"; return
  fi
  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
    print -r -- "$SUDO_USER"; return
  fi
  if [[ -e /dev/console ]] && u=$(stat -f %Su /dev/console 2>/dev/null) && [[ -n "$u" && "$u" != "root" ]]; then
    print -r -- "$u"; return
  fi
  if u=$(logname 2>/dev/null) && [[ -n "$u" && "$u" != "root" ]]; then
    print -r -- "$u"; return
  fi
  print -r -- "${USER:-$(whoami)}"
}

EL_USER="$(detect_el_user)"
EL_GROUP="staff"
# Resolve home dir via ~user (falls back to /Users/<user> if the user does
# not exist on this host, e.g. running --dry-run on Linux).
EL_HOME=""
{ EL_HOME=$(eval print -r -- "~${EL_USER}") } 2>/dev/null || EL_HOME=""
[[ -z "$EL_HOME" || "$EL_HOME" == "~${EL_USER}" ]] && EL_HOME="/Users/${EL_USER}"

SRC_AGENTS="/Library/LaunchAgents"
SRC_DAEMONS="/Library/LaunchDaemons"
DST_AGENTS="${EL_HOME}/Library/LaunchAgents"
DST_DAEMONS="${EL_HOME}/Library/LaunchDaemons"

DISABLED_SUFFIX=".disabled"

typeset -a LAUNCH_AGENTS
LAUNCH_AGENTS=(
  com.audiomovers.listento-talkback-xpc.plist
  com.logi.optionsplus.plist
  com.logitech.LogiRightSight.Agent.plist
  com.paceap.eden.licensed.agent.plist
  de.rme-audio.RMEfirefaceUSBAgent.plist
)

typeset -a LAUNCH_DAEMONS
LAUNCH_DAEMONS=(
  com.focusrite.ControlServer.plist
  com.logi.optionsplus.updater.plist
  com.motu.driver.usbmidi.dextproxy.launchd.plist
  com.native-instruments.NativeAccess.Helper2.plist
  com.paceap.eden.licensed.plist
  com.softube.installerdaemon.helper.plist
  com.windscribe.helper.macos.plist
)

# ---- State -----------------------------------------------------------------

MODE="apply"
DRY_RUN=0
APPLIED=0
SKIPPED=0
FAILED=0

# ---- Helpers ---------------------------------------------------------------

usage() {
  cat <<EOF
Usage: sudo ${ZSH_ARGZERO:-$0} [--undo|--redo|--dry-run|--help]

  (no flag)   Apply: copy el-only plists to ${EL_HOME}/Library/... ,
              chown ${EL_USER}:${EL_GROUP}, then rename originals in
              /Library/... to *${DISABLED_SUFFIX} so they no longer
              auto-start system-wide.

  --undo      Reverse: restore original names in /Library/... and
              remove the copies from ${EL_HOME}/Library/... .

  --redo      Same as default (explicit re-apply).

  --dry-run   Print actions without changing anything. Combine with
              --undo to preview undo.

  -h, --help  Show this help.

Requires root (sudo) because /Library writes and chown are used.
EOF
}

log()  { print -r -- "[mac-launch-cfg] $*"; }
warn() { print -r -- "[mac-launch-cfg][warn] $*" >&2; }
err()  { print -r -- "[mac-launch-cfg][err]  $*" >&2; }

run() {
  # run <cmd> [args...] — honors DRY_RUN
  if (( DRY_RUN )); then
    print -r -- "  DRY: $*"
  else
    "$@"
  fi
}

require_root() {
  if (( DRY_RUN )); then
    return 0
  fi
  if [[ $(id -u) -ne 0 ]]; then
    err "This script must be run as root. Try: sudo $0 $*"
    exit 1
  fi
}

ensure_dst_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    log "creating $dir"
    run mkdir -p "$dir"
    run chown "${EL_USER}:${EL_GROUP}" "$dir"
    run chmod 755 "$dir"
  fi
}

# apply_one <src_dir> <dst_dir> <plist>
apply_one() {
  local src_dir="$1" dst_dir="$2" name="$3"
  local src="${src_dir}/${name}"
  local dst="${dst_dir}/${name}"
  local disabled="${src}${DISABLED_SUFFIX}"

  if [[ ! -e "$src" && -e "$disabled" ]]; then
    log "skip  ${name}: already disabled at ${disabled}"
    (( SKIPPED++ )) || true
    return 0
  fi

  if [[ ! -e "$src" ]]; then
    warn "skip  ${name}: not found in ${src_dir}"
    (( SKIPPED++ )) || true
    return 0
  fi

  log "apply ${name}"

  # Copy to el's ~/Library (only if not already present)
  if [[ -e "$dst" ]]; then
    log "  copy exists, leaving: ${dst}"
  else
    run cp -p "$src" "$dst"
  fi
  run chown "${EL_USER}:${EL_GROUP}" "$dst"
  run chmod 644 "$dst"

  # Disable the system-wide original by renaming
  run mv "$src" "$disabled"

  (( APPLIED++ )) || true
}

# undo_one <src_dir> <dst_dir> <plist>
undo_one() {
  local src_dir="$1" dst_dir="$2" name="$3"
  local src="${src_dir}/${name}"
  local dst="${dst_dir}/${name}"
  local disabled="${src}${DISABLED_SUFFIX}"
  local did_something=0

  if [[ -e "$disabled" ]]; then
    if [[ -e "$src" ]]; then
      warn "undo  ${name}: both ${src} and ${disabled} exist; leaving disabled file in place"
    else
      log "undo  ${name}: restoring ${src}"
      run mv "$disabled" "$src"
      did_something=1
    fi
  else
    log "skip  ${name}: no ${disabled} to restore"
  fi

  if [[ -e "$dst" ]]; then
    log "  removing copy ${dst}"
    run rm -f "$dst"
    did_something=1
  fi

  if (( did_something )); then
    (( APPLIED++ )) || true
  else
    (( SKIPPED++ )) || true
  fi
}

# ---- Arg parse -------------------------------------------------------------

while (( $# > 0 )); do
  case "$1" in
    --undo)    MODE="undo" ;;
    --redo)    MODE="apply" ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) err "unknown argument: $1"; usage; exit 2 ;;
  esac
  shift
done

# ---- Main ------------------------------------------------------------------

require_root "$@"

log "mode=${MODE} dry_run=${DRY_RUN} target_user=${EL_USER} home=${EL_HOME}"

case "$MODE" in
  apply)
    ensure_dst_dir "$DST_AGENTS"
    ensure_dst_dir "$DST_DAEMONS"

    log "--- LaunchAgents ---"
    for p in "${LAUNCH_AGENTS[@]}"; do
      apply_one "$SRC_AGENTS" "$DST_AGENTS" "$p" || (( FAILED++ ))
    done

    log "--- LaunchDaemons ---"
    for p in "${LAUNCH_DAEMONS[@]}"; do
      apply_one "$SRC_DAEMONS" "$DST_DAEMONS" "$p" || (( FAILED++ ))
    done
    ;;

  undo)
    log "--- LaunchAgents ---"
    for p in "${LAUNCH_AGENTS[@]}"; do
      undo_one "$SRC_AGENTS" "$DST_AGENTS" "$p" || (( FAILED++ ))
    done

    log "--- LaunchDaemons ---"
    for p in "${LAUNCH_DAEMONS[@]}"; do
      undo_one "$SRC_DAEMONS" "$DST_DAEMONS" "$p" || (( FAILED++ ))
    done
    ;;
esac

log "done: changed=${APPLIED} skipped=${SKIPPED} failed=${FAILED}"
log "Note: changes take effect on next login/reboot. To load now for ${EL_USER},"
log "      have el run: launchctl load ~/Library/LaunchAgents/<plist>"
log "      For daemons, a reboot is the cleanest way to apply."
