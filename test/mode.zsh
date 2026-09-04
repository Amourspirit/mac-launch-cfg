#!/usr/bin/env zsh
# Tests for target_mode — the pure perms formula that preserves the source
# plist's execute (x) bits while normalizing read/write to the 644 baseline.
#
# target_mode src_octal -> octal string of (src & 0111) | 0644
#
# Run (from repo root): zsh test/mode.zsh

EL_SOURCED=1
source "$(dirname "$0")/../mac-launch-cfg.zsh"

fail=0
check() {
  local src="$1" expected="$2"
  local got
  got="$(target_mode "$src")"
  if [[ "$got" == "$expected" ]]; then
    print -r -- "ok   target_mode $src -> $got"
  else
    print -r -- "FAIL target_mode $src -> $got (expected $expected)"
    fail=1
  fi
}

# Executability cases from the spec: preserve source x bits, pin rw to 644.
check 644 644    # no exec anywhere -> stays 644
check 755 755    # owner+group+other exec (e.g. com.logi.optionsplus) -> preserved
check 774 754    # group write stripped; owner+group exec kept, other has no x
check 700 744    # owner-only rwx -> owner rw + x, others r-- only
check 111 755    # exec-only mode -> exec kept, rw normalized to 644
check 664 644    # no exec anywhere -> x not added, group write stripped
check 674 654    # group exec kept, group write stripped
check 4755 755   # setuid bit stripped (special bits never leak to the copy)
check 0644 644   # leading-zero input (macOS stat -f %Lp may pad to 4 digits)

if (( fail )); then
  print -r -- "FAILURES present" >&2
  exit 1
fi
print -r -- "all mode tests passed"
