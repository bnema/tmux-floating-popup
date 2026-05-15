# tmux Floating Popup

A TPM plugin that adds a floating terminal popup for tmux.
`Alt-f` toggles the popup without losing its shell state, while `Esc` closes it and destroys that popup session.
The next `Alt-f` creates a fresh numbered popup session.

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
| `@floating-popup-session-name` | `tmux-floating-popup` | Prefix used for numbered popup sessions such as `tmux-floating-popup-1` |
| `@floating-popup-title` | `Floating Popup` | Popup title passed to `display-popup -T` |

Example:

```tmux
set -g @floating-popup-key 'M-f'
set -g @floating-popup-width '80%'
set -g @floating-popup-height '80%'
set -g @floating-popup-session-name 'scratch-popup'
set -g @floating-popup-title 'Scratch'
```

## Usage

- Press `Alt-f` from any normal tmux pane to open the popup.
- Press `Alt-f` while the popup is focused to hide it and preserve that popup session.
- Press `Esc` while the popup is focused to close it and destroy that popup session.
- Press `Alt-f` again after hiding to resume the same popup shell.
- Press `Alt-f` again after `Esc` to start a fresh numbered popup session.

## Behavior notes

- The popup is backed by a tmux session instead of a one-shot shell.
- `Alt-f` hides the popup by detaching that popup client, so shells, editors, and scrollback remain available when you reopen it.
- `Esc` destroys the popup session completely, so the next open starts fresh.
- The first open creates a numbered session such as `tmux-floating-popup-1`; later `Esc` closes create newer ids instead of reusing the old session name.
- Popup sessions have `status off`, so the popup looks like a normal shell rather than a nested tmux UI.
- The plugin binds `Escape` at the root table and passes it through everywhere except popup sessions, where it closes the popup session.

## Troubleshooting

### Nothing happens when I press `Alt-f`

Check that the plugin is loaded:

```bash
tmux list-keys -T root M-f
tmux list-keys -T root Escape
```

You should see the root `Alt-f` binding for `scripts/open-popup.sh` and a conditional root `Escape` binding for `scripts/close-popup.sh`.

### The popup opens but starts fresh every time

If that happens after `Alt-f` hide/show, check whether the popup session was destroyed with `Esc` or killed externally.
Also reload the plugin after changing `@floating-popup-session-name`.

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
