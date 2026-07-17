# Herdr Notify (Windows)

Raise a native **Windows 11 toast** when a herdr agent needs your attention — so you can run
several agents and get pinged the moment one finishes or blocks, without watching the panes.

It notifies on two status edges:

- `working → done` / `working → idle` → **"Turn finished"**
- `working → blocked` → **"Needs input"**

The toast shows the agent and workspace, e.g. `claude · my-project`.

## How it works

Hooked to herdr's `pane.agent_status_changed` event, `notify.ps1` reads `herdr pane list` and diffs
each agent pane's current status against the last-seen status (a small JSON state file in the
plugin's state dir), so it fires exactly on the transition — not on every event, and never on
startup. Toasts are delivered with the built-in Windows WinRT API (no BurntToast/Node needed) under
the built-in Windows PowerShell App ID.

## Requirements

- Herdr `0.7.0` or newer, on **Windows** (herdr's Windows preview).
- Windows PowerShell 5.1 (built in).
- Notifications enabled and Focus Assist off for the toasts to appear.

## Install

Local dev link (from this folder):

```powershell
herdr plugin link .
```

## Test

Confirm toasts actually appear on your machine:

```powershell
herdr plugin action invoke aclima.herdr-notify.test
```

You should get a "Test notification - setup OK" toast. If nothing appears, check
**Settings → System → Notifications** (enabled) and **Focus Assist / Do not disturb** (off).

## Notes

- Only agent panes are considered; the `unknown` status is treated as transient and never notifies.
- One state file tracks all panes, so multiple concurrent agents each notify independently.

## License

MIT
