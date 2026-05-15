# tmux Floating Popup

A TPM plugin that adds a persistent floating terminal popup for tmux.
It opens with `Alt-f`, hides with `Alt-f` again, and also hides with `Esc`.
The content stays alive because the popup always reattaches to the same dedicated tmux session.

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
| `@floating-popup-key` | `M-f` | Key used in both the root and popup key tables |
| `@floating-popup-width` | `80%` | Popup width passed to `display-popup` |
| `@floating-popup-height` | `80%` | Popup height passed to `display-popup` |
| `@floating-popup-session-name` | `tmux-floating-popup` | Dedicated tmux session reused for the popup |
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
- Press `Alt-f` while the popup is focused to hide it.
- Press `Esc` to hide it with tmux's built-in popup close behavior.
- Reopen it later and you come back to the same popup session state.

## Behavior notes

- The popup is backed by a dedicated tmux session instead of a one-shot shell.
- Hiding the popup does not kill that session, so shells, editors, and scrollback remain available when you reopen it.
- The popup opens in the current pane path the first time the session is created.
- On later opens, tmux reattaches to the existing popup session instead of creating a new one.
- The plugin uses the `popup` key table so the same key can close the popup even while the overlay has focus.

## Troubleshooting

### Nothing happens when I press `Alt-f`

Check that the plugin is loaded:

```bash
tmux list-keys -T root M-f
tmux list-keys -T popup M-f
```

You should see bindings for `scripts/open-popup.sh` and `scripts/close-popup.sh`.

### The popup opens but starts fresh every time

Check whether you changed `@floating-popup-session-name` dynamically in a running tmux server.
If you did, reopen tmux or reload the plugin after setting the option.

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
