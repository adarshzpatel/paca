#!/usr/bin/env bash
# Start or stop a throwaway herdr server named "paca-test" for experiments,
# so nothing touches your real session.
#
#   scripts/test-session.sh start   start server + one workspace in this repo
#   scripts/test-session.sh stop
set -euo pipefail
NAME=${PACA_TEST_SESSION:-paca-test}
case "${1:-start}" in
  start)
    env -u HERDR_ENV -u HERDR_SOCKET_PATH -u HERDR_PANE_ID -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID \
      nohup herdr --session "$NAME" server >/dev/null 2>&1 &
    for _ in $(seq 20); do herdr --session "$NAME" status server >/dev/null 2>&1 && break; sleep 0.25; done
    # Only the first start needs a workspace; herdr restores earlier ones.
    if ! herdr --session "$NAME" workspace list | grep -q '"workspace_id"'; then
      herdr --session "$NAME" workspace create --cwd "$(cd "$(dirname "$0")/.." && pwd)" >/dev/null
    fi
    echo "started herdr session $NAME"
    ;;
  stop) herdr session stop "$NAME" ;;
  *) echo "usage: $0 start|stop" >&2; exit 2 ;;
esac
