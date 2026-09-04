# AGENTS.md

## What this repo is

A single-purpose zsh tool that runs on **macOS** (Mac Studio, multi-user)
to relocate `current user`-only LaunchAgents/LaunchDaemons out of `/Library/...`
into `~/Library/...` so they don't start under other users
(e.g. `user2`). See `README.md` for the issue write-up.

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
- Unit test for the mode-preservation formula: `zsh test/mode.zsh`
- Preview logic on any host: `./mac-launch-cfg.zsh --dry-run`
  (also `--undo --dry-run`)
- Real run (Mac only, root): `sudo ./mac-launch-cfg.zsh [--undo|--redo]`

There is no CI. `zsh -n`, `test/mode.zsh`, and `--dry-run` are the
verification steps.

## Conventions / gotchas

- Default action is **apply**. `--redo` is an explicit alias for apply.
- Disabled-file convention: original renamed to `<name>.plist.disabled`
  in `/Library/...`. Undo depends on this exact suffix
  (`DISABLED_SUFFIX` constant).
- Script is **idempotent per file** and derives state purely from
  filesystem presence — no state file. Do not add one without reason;
  the user explicitly chose the hardcoded-list approach.
- Non-destructive contract (documented in README): never delete
  originals, never overwrite existing copies in `~/Library`, always
  reversible via `--undo`. Preserve this when editing.
- Uses `set -u` + `setopt ERR_EXIT PIPE_FAIL`. Counter increments use
  `(( VAR++ )) || true` because `((x++))` returns non-zero when the
  pre-increment value is 0 and would abort under `ERR_EXIT`.
- Root check is skipped under `--dry-run` so previews work as any user
  on any OS.
- Ownership target is `<user>:staff`, perms `755` for created dirs, and
  `644` **plus the source's `x` bits** for plists — `target_mode`
  computes `(src & 0111) | 0644` so executable plists (e.g.
  `com.logi.optionsplus.plist`, mode `755`) stay executable. See
  `test/mode.zsh` for the formula's expected values.
- `EL_SOURCED=1` sources `mac-launch-cfg.zsh` as a library (function
  definitions only, skipping main) so `test/mode.zsh` can unit-test
  `target_mode`. The main block is guarded by `if (( ! EL_SOURCED ))`.
- Effects: LaunchAgents load at next login for `<user>`; LaunchDaemons
  require reboot. Do not add auto-`launchctl load/unload` — the script
  runs as root but the agents belong to `current users`'s session.

## Agent skills

### Issue tracker

Issues are tracked as local markdown files under `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical triage roles, each label string equal to its name. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: root `CONTEXT.md` + `docs/adr/`. See `docs/agents/domain.md`.
