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
`.codex_config` precedence rule (defaults < config < flags), and the passthrough
behavior. It is printed for the `help` command, which exits before tool checks.
