# mac-launch-cfg

A single `zsh` script to isolate the `el` user's LaunchAgents and
LaunchDaemons on a shared Mac Studio (M3 Ultra, 256 GB RAM) so they no
longer auto-start for other users such as `paul`.

## The issue

The Mac has two accounts:

- `el`  — local usage. Has Logitech, RME, Focusrite, MOTU, Native
  Instruments, Softube, Windscribe, Pace/Eden, AudioMovers, etc.
  installed. Their helpers register system-wide in
  `/Library/LaunchAgents` and `/Library/LaunchDaemons`.
- `paul` — remote development. Does not need any of `el`'s peripheral
  or DAW helper software.

Because those plists live in `/Library/...`, macOS launches them for
**every** user session and for the system as a whole. When `paul`
logs in before `el`, `el`'s helpers spin up under `paul`, and when
`el` then logs in, `el`'s mouse and keyboard misbehave because the
Logitech agents are already owned by another session.

## The solution

For each `el`-only plist:

1. Copy it from `/Library/LaunchAgents` (or `/Library/LaunchDaemons`)
   into `/Users/el/Library/LaunchAgents` (or `.../LaunchDaemons`).
2. `chown el:wheel` and `chmod 644` the copy.
3. Rename the original in `/Library/...` by appending `.disabled` so
   `launchd` no longer picks it up at boot / login.

The helpers now only run when `el` logs in, and `paul`'s remote
sessions are clean.

### LaunchAgents moved out of `/Library/LaunchAgents`

- `com.audiomovers.listento-talkback-xpc.plist`
- `com.logi.optionsplus.plist`
- `com.logitech.LogiRightSight.Agent.plist`
- `com.paceap.eden.licensed.agent.plist`
- `de.rme-audio.RMEfirefaceUSBAgent.plist`

### LaunchDaemons moved out of `/Library/LaunchDaemons`

- `com.focusrite.ControlServer.plist`
- `com.logi.optionsplus.updater.plist`
- `com.motu.driver.usbmidi.dextproxy.launchd.plist`
- `com.native-instruments.NativeAccess.Helper2.plist`
- `com.paceap.eden.licensed.plist`
- `com.softube.installerdaemon.helper.plist`
- `com.windscribe.helper.macos.plist`

## Usage

The script writes to `/Library` and changes ownership, so `sudo` is
required for all non-dry-run invocations.

```zsh
# Apply (default): copy to ~el/Library and disable /Library originals
sudo ./mac-launch-cfg.zsh

# Preview apply without making any changes
./mac-launch-cfg.zsh --dry-run

# Undo: restore original /Library names, remove copies from ~el/Library
sudo ./mac-launch-cfg.zsh --undo

# Preview undo without making any changes
./mac-launch-cfg.zsh --undo --dry-run

# Redo (explicit re-apply; same as default)
sudo ./mac-launch-cfg.zsh --redo

# Help
./mac-launch-cfg.zsh --help
```

Make it executable once:

```zsh
chmod +x ./mac-launch-cfg.zsh
```

### Why `sudo`?

- `/Library/LaunchAgents` and `/Library/LaunchDaemons` are owned by
  `root:wheel` — renaming files there requires root.
- The copies placed in `/Users/el/Library/...` are `chown`ed to
  `el:wheel`, which also requires root.
- `--dry-run` does not touch the filesystem and does not require root.

### When do changes take effect?

- LaunchAgents load at user login. `el` will need to log out and back
  in (or run `launchctl load ~/Library/LaunchAgents/<plist>` manually).
- LaunchDaemons load at boot. A reboot is the cleanest way to apply.

## Non-destructive by design

- **Nothing is deleted on apply.** Originals in `/Library/...` are
  *renamed* to `<name>.plist.disabled`, not removed. They can be
  restored at any time with `--undo`.
- **Copies never overwrite existing files.** If a plist already
  exists in `~el/Library/...`, the existing copy is left alone
  (ownership/permissions are still normalized).
- **Idempotent.** Re-running apply skips any plist that is already
  disabled. Re-running undo skips any plist that is already restored.
- **Reversible.** `--undo` moves each `*.plist.disabled` back to
  `*.plist` in `/Library/...` and removes the copy from
  `~el/Library/...`, returning the system to its original state.
- **Previewable.** `--dry-run` prints every action (`cp`, `mv`,
  `chown`, `chmod`, `rm`) it would perform without touching disk.
- **Explicit list.** The script only touches the plists explicitly
  named in the arrays at the top of `mac-launch-cfg.zsh`. Nothing
  else in `/Library/LaunchAgents` or `/Library/LaunchDaemons` is
  considered.

## Recovery if something goes wrong

Everything the script does is a `mv` or a `cp` of a plist file:

- To restore a single agent manually:
  ```zsh
  sudo mv /Library/LaunchAgents/<name>.plist.disabled \
          /Library/LaunchAgents/<name>.plist
  ```
- To remove a single copy manually:
  ```zsh
  sudo rm /Users/el/Library/LaunchAgents/<name>.plist
  ```
- Or just run `sudo ./mac-launch-cfg.zsh --undo` to reverse everything
  the script did.
