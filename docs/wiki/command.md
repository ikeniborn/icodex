# Command

## Overview

`lib/command/args.sh` parses icodex's own flags and separates codex passthrough.

It sets `ICODEX_CMD` and a few state variables, collecting everything after the
first non-flag (or after `--`) as passthrough. It also prints the help text. See
[[architecture#Command dispatch]] and [[launch#Proxy persist and apply]].

## Flag parsing

`parse_args` loops over arguments and maps each known flag to state.

`--proxy <url>` sets `ICODEX_SET_PROXY`, `--no-proxy` sets `ICODEX_DISABLE_PROXY`,
`--full-access` sets `ICODEX_FULL_ACCESS` to escalate the sandbox to
`danger-full-access` for the run (consumed by [[config#Sandbox mode]]), and
`--clear`/`--update`/`--install`/`--version`/`--help` set `ICODEX_CMD`. A missing
`--proxy` value is an error. The default command is `run`.

## Passthrough collection

Anything after `--`, or the first unrecognized token, becomes codex passthrough.

It is appended to the `ICODEX_PASSTHROUGH` array and parsing stops. The array is
expanded verbatim into the codex invocation by [[launch#Final exec]], so codex
subcommands and options pass through unchanged.

## Help text

`print_help` emits a static usage block via a quoted heredoc.

It covers the synopsis, each icodex flag with a one-line description, the
`.codex_config` precedence rule (defaults < config < flags), the `ICODEX_MODE`
run-profile presets (`ro` / `safe` / `full-ask` / `full-auto`), and the passthrough
behavior. It is printed for the `help` command, which exits before tool checks.

## Launch sequence

On the default `run` path, after flags are parsed and `install`/`update` are ruled out,
`main()` calls in order: `setup_codex_home`, `apply_mode`, `ensure_project_trust`,
`ensure_launcher_binary_permission`, `ensure_superpowers_wiring`, then
`ensure_caveman_wiring` (gated on `ICODEX_CAVEMAN_MODE` — renders the caveman
`AGENTS.md` block and merges the `UserPromptSubmit` hook into the home `hooks.json`),
followed by binary and `uv` checks, optional proxy setup, and finally `launch_codex`.
See [[caveman#Launch-path wiring]] and [[architecture#Default run path]].
