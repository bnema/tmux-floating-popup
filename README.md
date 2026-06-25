# tmux Floating Popup

A TPM plugin that adds a floating terminal popup for tmux.
`Alt-f` toggles the popup without losing its shell state, while `Esc` closes it only when the popup is sitting at a plain shell prompt.
When an application such as Neovim is running inside the popup, `Esc` is passed through to that application.
Each parent tmux session owns at most one internal popup session named `__floating-popup-<id>`.

## Requirements

- `tmux 3.6+`
- `bash`

## Installation

### With Tmux Plugin Manager

Add this to `~/.tmux.conf`:

```tmux
set -g @plugin 'bnema/tmux-floating-popup'
```

If you are using a fork, replace `bnema` with your GitHub user or organization.

Keep TPM itself loaded at the bottom of the file:

```tmux
run '~/.tmux/plugins/tpm/tpm'
```

Then reload tmux or press `prefix + I` inside tmux.

### Manual install

Clone the repository into the standard TPM plugin directory:

```bash
git clone https://github.com/bnema/tmux-floating-popup ~/.tmux/plugins/tmux-floating-popup
```

Then add this to `~/.tmux.conf`:

```tmux
run-shell ~/.tmux/plugins/tmux-floating-popup/tmux-floating-popup.tmux
```

Reload tmux:

```bash
tmux source-file ~/.tmux.conf
```

### Quick local testing

For local development from this checkout:

```bash
make install
```

That symlinks this repository into `~/.tmux/plugins/tmux-floating-popup`.

To remove the test install:

```bash
make uninstall
```

## Configuration

Configure the plugin with tmux user options in `~/.tmux.conf`.

| Option | Default | Meaning |
| --- | --- | --- |
| `@floating-popup-key` | `M-f` | Key used to open the popup from normal tmux clients and hide it from inside the popup session |
| `@floating-popup-width` | `80%` | Popup width passed to `display-popup` |
| `@floating-popup-height` | `80%` | Popup height passed to `display-popup` |
| `@floating-popup-title` | `Floating Popup` | Popup title passed to `display-popup -T` |
| `@floating-popup-warmup` | `off` | Pre-create hidden popup sessions for parent tmux sessions on client attach/session changes so the first visible open can often reuse an already-started shell |

Example:

```tmux
set -g @floating-popup-key 'M-f'
set -g @floating-popup-width '80%'
set -g @floating-popup-height '80%'
set -g @floating-popup-title 'Scratch'
set -g @floating-popup-warmup 'on'
```

## Usage

- Press `Alt-f` from any normal tmux pane to open the popup.
- Press `Alt-f` while the popup is focused to hide it and preserve that popup session.
- Press `Esc` while the popup is focused at a shell prompt to close it and destroy that popup session.
- Press `Esc` while an application is running inside the popup to send `Esc` to that application.
- If the popup client is switched to another tmux session, press `Esc` or `Alt-f` to close only the floating popup client without killing that session.
- Press `Alt-f` again after hiding to resume the same popup shell for that parent tmux session.
- Two clients attached to the same parent tmux session share the same popup session when it exists.
- After closing with `Esc`, press `Alt-f` to start a fresh internal popup session for that parent tmux session.

## Behavior notes

- The popup is backed by a tmux session instead of a one-shot shell.
- Each parent tmux session owns at most one internal popup session. Two clients attached to the same parent session open, hide, and resume that shared popup session.
- `@floating-popup-warmup on` pre-creates hidden popup sessions in the background for parent sessions on client attach and session switches, so the first visible open can often skip shell startup work.
- If a warmed session has never been opened and the requested pane path changes before the first visible open, the plugin refreshes that unused warmed session so the popup still starts in the current path.
- `Alt-f` hides the popup by detaching that popup client, so shells, editors, and scrollback remain available when you reopen it.
- `Esc` destroys the internal popup session completely only when the active popup command is a known shell, so the next open starts fresh.
- The plugin tracks the popup client separately from the internal popup session. If that client is switched to a normal tmux session, closing the popup detaches only the popup client and never destroys the normal session.
- Cleanup removes internal popup sessions whose parent tmux session no longer exists.
- The first open for a parent creates an internal session such as `__floating-popup-1`; subsequent opens after closing with `Esc` create newer ids instead of reusing the old session name.
- Popup sessions have `status off`, so the popup looks like a normal shell rather than a nested tmux UI.
- The plugin binds `Escape` at the root table and uses `#{pane_current_command}` inside internal popup sessions: known shells close the popup, other commands receive `Escape`.

## Troubleshooting

### Nothing happens when I press `Alt-f`

Check that the plugin is loaded:

```bash
tmux list-keys -T root M-f
tmux list-keys -T root Escape
```

You should see the root `Alt-f` binding for `scripts/open-popup.sh` and the root `Escape` binding for `scripts/smart-escape.sh`.

### The popup opens but starts fresh every time

If that happens after `Alt-f` hide/show, check whether the popup session was destroyed with `Esc` or killed externally.

### I want a different key

Set:

```tmux
set -g @floating-popup-key 'M-Space'
```

Then reload tmux:

```bash
tmux source-file ~/.tmux.conf
```

## Development notes

The implementation is shell-first and is designed to be testable against isolated tmux sockets.
Human-visible UI checks are still useful, but the core popup/session behavior can be validated headlessly with `tmux -L <socket>`.
