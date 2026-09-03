# AGENTS.md

## What this repo is

A single-purpose zsh tool that runs on **macOS** (Mac Studio, multi-user)
to relocate `current user`-only LaunchAgents/LaunchDaemons out of `/Library/...`
into `~/Library/...` so they don't start under other users
(e.g. `paul`). See `README.md` for the issue write-up.

Development happens on a Linux box (`~/scripts/mac-launch-cfg/`);
the script only actually runs on the target Mac.

## Layout

- `mac-launch-cfg.zsh` — the entire tool. Two hardcoded arrays at the
  top (`LAUNCH_AGENTS`, `LAUNCH_DAEMONS`) are the source of truth for
  which plists are touched. Edit those arrays to change scope.
- `README.md` — user-facing docs. Keep the plist lists in README and
  in the script in sync.
- `tmp/` — gitignored scratch.

## Commands

- Syntax check (safe on Linux): `zsh -n mac-launch-cfg.zsh`
- Preview logic on any host: `./mac-launch-cfg.zsh --dry-run`
  (also `--undo --dry-run`)
- Real run (Mac only, root): `sudo ./mac-launch-cfg.zsh [--undo|--redo]`

There is no test suite, no linter config, no CI. Dry-run is the
verification step.

## Conventions / gotchas

- Default action is **apply**. `--redo` is an explicit alias for apply.
- Disabled-file convention: original renamed to `<name>.plist.disabled`
  in `/Library/...`. Undo depends on this exact suffix
  (`DISABLED_SUFFIX` constant).
- Script is **idempotent per file** and derives state purely from
  filesystem presence — no state file. Do not add one without reason;
  the user explicitly chose the hardcoded-list approach.
- Non-destructive contract (documented in README): never delete
  originals, never overwrite existing copies in `~el/Library`, always
  reversible via `--undo`. Preserve this when editing.
- Uses `set -u` + `setopt ERR_EXIT PIPE_FAIL`. Counter increments use
  `(( VAR++ )) || true` because `((x++))` returns non-zero when the
  pre-increment value is 0 and would abort under `ERR_EXIT`.
- Root check is skipped under `--dry-run` so previews work as any user
  on any OS.
- Ownership target is `el:wheel`, perms `644` for plists, `755` for
  created dirs. Matches macOS `~/Library/Launch*` norms.
- Effects: LaunchAgents load at next login for `el`; LaunchDaemons
  require reboot. Do not add auto-`launchctl load/unload` — the script
  runs as root but the agents belong to `current users`'s session.
