# shellcheck shell=bash
# Interactive-prompt helper shared by the helper scripts.
#
# Scripts are run both by a human in a terminal AND non-interactively by CI and
# the Setup Wizard's job runner (no TTY, stdin closed). A bare `read` under
# `set -euo pipefail` aborts the whole script on EOF, so every prompt must be
# guarded with `is_interactive` and fall back to a default / env var.
#
# Non-interactive is detected as: stdin is not a TTY, or one of the override
# flags is set. The wizard runner also feeds the process /dev/null as stdin.

is_interactive() {
  [[ -t 0 && "${ASSUME_YES:-}" != "1" && "${NON_INTERACTIVE:-}" != "1" ]]
}
