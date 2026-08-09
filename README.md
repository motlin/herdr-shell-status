# Herdr shell status

Herdr lifecycle reporting for commands entered in an interactive Zsh. Commands appear as working while they run, idle when they succeed, and blocked when they fail.

The integration activates only in the root interactive shell of a Herdr pane. Nested interactive shells—including shells launched by Claude or Codex—do not report command activity. Native agent CLIs receive lifecycle ownership when launched, so their richer Herdr integrations continue to work.

## Install

Clone the repository, then source the plugin near the end of `.zshrc`:

```zsh
if [[ -r "$HOME/projects/herdr-shell-status/herdr-shell-status.plugin.zsh" ]]; then
  source "$HOME/projects/herdr-shell-status/herdr-shell-status.plugin.zsh"
fi
```

The plugin requires `herdr`, `jq`, `HERDR_ENV=1`, and `HERDR_PANE_ID`. It fails open when any requirement is unavailable.

## Automatic reporting

Every command entered in the pane's root Zsh reports through the `user:zsh-command` source with the `cli` label:

- working while the command runs
- idle after exit status 0 or a common interruption status
- blocked after any other nonzero status

Command text and arguments are never sent to Herdr. A failure message includes only the exit status.

The plugin releases its lifecycle authority before `exec`, `herdr-run`, and known native agent CLIs. Set `HERDR_SHELL_STATUS_DELEGATES` before sourcing the plugin to replace the default delegate list.

Use `herdr_shell_status_disable` or `herdr_shell_status_enable` to control reporting in the current shell.

## Explicit wrapper

Use `herdr-run` when a script, automation, or non-Zsh shell should report one command:

```console
herdr-run --label build -- vp build
```

The wrapper preserves the wrapped command's exit status. Its final state remains visible until the pane receives focus, then a detached watcher releases the lifecycle entry. Outside Herdr, it directly executes the command.

Add the repository's `bin` directory to `PATH` to invoke `herdr-run` by name.

## Validate

```console
bin/check
```

The test suite uses a fake Herdr executable and does not modify live pane state.
