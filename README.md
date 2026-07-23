# Herdr Notify WSL

Raise a native **Windows 11 toast** when a herdr agent needs your attention — for the case where
**herdr runs inside WSL** but you want the notification on the Windows host. Run several agents and
get pinged the moment one finishes or blocks, without watching the panes.

> Based on [`aclima01/herdr-notify-windows`](https://github.com/aclima01/herdr-notify-windows),
> which targets herdr running **natively on Windows**. This fork adapts it for herdr running in
> **WSL (Linux)**: the status query/diff runs in bash against the Linux `herdr` binary, and it only
> crosses into Windows (via `powershell.exe`) to raise the toast itself.

It notifies on two status edges:

- `working → done` / `working → idle` → **"Turn finished"**
- `working → blocked` → **"Needs input"**

The toast shows the agent and workspace, e.g. `claude · my-project`.

## How it works

Hooked to herdr's `pane.agent_status_changed` event, `notify.sh` reads `herdr pane list` and diffs
each agent pane's current status against the last-seen status (a small JSON state file in the
plugin's state dir), so it fires exactly on the transition — not on every event, and never on
startup. The diff runs in bash with `jq`; only the toast is delegated to `powershell.exe`, which
uses the built-in Windows WinRT API (no BurntToast/Node needed) under the built-in Windows
PowerShell App ID. Toast text is base64-passed across the WSL→Windows boundary to avoid quoting
issues.

The original PowerShell implementation (`notify.ps1`, `notify.tests.ps1`) is kept in the repo for
reference and for anyone running herdr natively on Windows.

## Requirements

- Herdr `0.7.0` or newer, running inside **WSL** (Linux).
- `bash`, `jq`, and `base64` in WSL (standard on most distros; `apt install jq` if missing).
- `powershell.exe` reachable from WSL (default on Windows; it lives under
  `C:\Windows\System32\WindowsPowerShell\v1.0\`).
- Windows notifications enabled and Focus Assist / Do not disturb off for the toasts to appear.

## Install

Local dev link (from this folder, inside WSL):

```bash
herdr plugin link .
```

## Test

Confirm toasts actually appear on your Windows host:

```bash
herdr plugin action invoke aclima.herdr-notify-windows.test
```

You should get a "Test notification - setup OK" toast. If nothing appears, check
**Settings → System → Notifications** (enabled) and **Focus Assist / Do not disturb** (off).

## Notes

- Only agent panes are considered; the `unknown` status is treated as transient and never notifies.
- One state file tracks all panes, so multiple concurrent agents each notify independently.

## Credits

- Upstream: [`aclima01/herdr-notify-windows`](https://github.com/aclima01/herdr-notify-windows) (MIT).

## License

MIT
