#!/usr/bin/env bash
# Run every write action Paca uses against a throwaway herdr session and check
# each result in a fresh snapshot. Never touches your default session.
#
#   scripts/smoke-actions.sh                    uses paca-test, starting it if needed
#   PACA_TEST_SESSION=other scripts/smoke-actions.sh
set -euo pipefail
cd "$(dirname "$0")/.."
NAME=${PACA_TEST_SESSION:-paca-test}
if ! herdr --session "$NAME" status server >/dev/null 2>&1; then
  PACA_TEST_SESSION="$NAME" scripts/test-session.sh start
fi
swift build --product paca-probe >/dev/null
exec .build/debug/paca-probe --session "$NAME" smoke
