#!/usr/bin/env bash
# Build a throwaway herdr session full of made-up projects, agents and shells, for
# screenshots and demos. Agent states come from `herdr pane report-agent`, so no real
# agent runs and nothing leaves the machine. Rerunning rebuilds the session from scratch.
#
#   scripts/demo-session.sh              build "paca-demo"
#   scripts/demo-session.sh my-demo      another name (must start with paca-demo)
#   scripts/demo-session.sh stop         stop and delete it
set -euo pipefail
cd "$(dirname "$0")/.."

NAME=${PACA_DEMO_SESSION:-paca-demo}
if [[ "${1:-}" == stop ]]; then
  herdr session stop "$NAME" >/dev/null 2>&1 || true
  herdr session delete "$NAME" >/dev/null 2>&1 || true
  echo "removed herdr session $NAME"
  exit 0
fi
NAME=${1:-$NAME}
# Rebuilding deletes the session, so refuse anything that could be a real one.
[[ "$NAME" == paca-demo* ]] || { echo "session name must start with paca-demo" >&2; exit 1; }

ROOT=/tmp/paca-demo
h() { herdr --session "$NAME" "$@"; }

herdr session stop "$NAME" >/dev/null 2>&1 || true
herdr session delete "$NAME" >/dev/null 2>&1 || true
rm -rf "$ROOT"
mkdir -p "$ROOT/transcripts"
for project in lumen-web ledger-api orbit-ios infra; do
  mkdir -p "$ROOT/$project"
  git -C "$ROOT/$project" init -q -b main
done

env -u HERDR_ENV -u HERDR_SOCKET_PATH -u HERDR_PANE_ID -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID \
  nohup herdr --session "$NAME" server >/dev/null 2>&1 &
for _ in $(seq 40); do h status server >/dev/null 2>&1 && break; sleep 0.25; done

# Transcripts: {g} green, {r} red, {y} yellow, {b} blue, {m} magenta, {d} dim, {B} bold, {x} reset.
transcript() {
  sed -e $'s/{g}/\033[32m/g' -e $'s/{r}/\033[31m/g' -e $'s/{y}/\033[33m/g' -e $'s/{b}/\033[34m/g' \
      -e $'s/{m}/\033[35m/g' -e $'s/{d}/\033[2m/g' -e $'s/{B}/\033[1m/g' -e $'s/{x}/\033[0m/g' \
      > "$ROOT/transcripts/$1.txt"
}

transcript pricing <<'EOF'
{B}> Redesign the pricing page: three tiers, yearly toggle, and a comparison table{x}

{g}●{x} Reading the current page and the design tokens
  {d}└ app/pricing/page.tsx, components/ui/tokens.ts, content/plans.json{x}

{g}●{x} Plan
  {d}1.{x} Split PlanCard out of page.tsx and drive it from plans.json
  {d}2.{x} Add a monthly / yearly toggle that keeps the choice in the URL
  {d}3.{x} Build the comparison table from the same plan data
  {d}4.{x} Snapshot tests for all three breakpoints

{g}●{x} Update {B}components/pricing/PlanCard.tsx{x}
  {d}└ 64 additions{x}
    {g}+ export function PlanCard({ plan, cycle }: PlanCardProps) {{x}
    {g}+   const price = cycle === "yearly" ? plan.yearly / 12 : plan.monthly{x}
    {g}+   return ({x}
    {g}+     <Card highlighted={plan.recommended}>{x}

{g}●{x} Update {B}app/pricing/page.tsx{x}
  {d}└ 18 additions, 141 removals{x}

{g}●{x} Run {B}pnpm test pricing{x}
  {d}└{x} {g}✓{x} PlanCard renders yearly prices {d}(12 ms){x}
    {g}✓{x} toggle keeps ?cycle=yearly {d}(8 ms){x}
    {g}✓{x} comparison table lists every feature {d}(21 ms){x}

{y}✻{x} Building the comparison table… {d}(2m 14s · esc to interrupt){x}
EOF

transcript idempotency <<'EOF'
{B}> Add idempotency keys to POST /payments{x}

{g}●{x} Added {B}Idempotency-Key{x} handling in {B}src/payments/create.ts{x}
  {d}└ keys live for 24 h in the idempotency_keys table{x}

{g}●{x} Wrote migration {B}db/migrations/0042_idempotency_keys.sql{x}
    {g}+ CREATE TABLE idempotency_keys ({x}
    {g}+   key        text PRIMARY KEY,{x}
    {g}+   request    jsonb NOT NULL,{x}
    {g}+   response   jsonb,{x}
    {g}+   created_at timestamptz NOT NULL DEFAULT now(){x}
    {g}+ );{x}

{y}?{x} {B}Run the migration against the staging database?{x}

  {b}❯ 1. Yes, run it{x}
    2. Yes, and don't ask again for migrations
    3. No, show me the SQL first
EOF

transcript refunds <<'EOF'
{B}> Write integration tests for the refunds flow{x}

{g}●{x} Found 6 refund paths in {B}src/refunds/{x}
{g}●{x} Created {B}test/refunds.integration.test.ts{x} {d}(212 lines){x}
{g}●{x} Run {B}pnpm vitest refunds{x}
  {d}└{x} {g}✓{x} full refund restores the balance
    {g}✓{x} partial refund keeps the remainder
    {r}✗{x} refund after payout is rejected
      {d}expected 409, got 500{x}

{g}●{x} The payout check throws before the status check. Fixing {B}src/refunds/guard.ts{x}

{y}✻{x} Rerunning tests…
EOF

transcript hydration <<'EOF'
{B}> Fix the hydration warning on /docs{x}

{g}●{x} The table of contents read window.location during render
{g}●{x} Moved it into useEffect in {B}components/docs/Toc.tsx{x}
{g}●{x} Run {B}pnpm build && pnpm test docs{x}
  {d}└{x} {g}✓{x} 31 passed

{g}Done.{x} No hydration warnings on /docs, /docs/api or /docs/guides.
EOF

transcript devserver <<'EOF'
{d}$ pnpm dev{x}

  {m}▲ Next.js 15.4{x}
  - Local:   http://localhost:3000
  - Network: http://192.168.1.24:3000

 {g}✓{x} Ready in 1.2s
 {g}✓{x} Compiled /pricing in 412ms
 {g}✓{x} Compiled /docs in 238ms
 GET /pricing {g}200{x} in 61ms
 GET /pricing?cycle=yearly {g}200{x} in 18ms
EOF

transcript settings <<'EOF'
{B}> Migrate the settings screen to SwiftUI{x}

{g}●{x} Read {B}SettingsViewController.swift{x} {d}(612 lines){x}
{g}●{x} Created {B}SettingsView.swift{x}, {B}SettingsModel.swift{x}
{g}●{x} Build {B}xcodebuild -scheme Orbit{x}
  {d}└{x} {g}✓{x} Build succeeded

Waiting for your next message.
EOF

transcript terraform <<'EOF'
{B}> Bump the Terraform providers and fix any drift{x}

{g}●{x} aws 5.62 → 6.4, cloudflare 4.39 → 5.2
{g}●{x} Run {B}terraform plan{x}
  {d}└{x} {y}~{x} 3 to change, {g}+{x} 1 to add, {r}-{x} 0 to destroy

{y}✻{x} Reading the cloudflare 5.0 upgrade guide…
EOF

transcript alerts <<'EOF'
{B}> Tune the autoscaling alerts so they stop paging at night{x}

{g}●{x} Raised the CPU threshold to 80% for 10 minutes
{g}●{x} Added a quiet window for the batch jobs at 02:00 UTC

{g}Done.{x} 4 alert rules changed, 0 removed.
EOF

transcript gitlog <<'EOF'
{d}$ git log --oneline -6{x}
{y}a41c9e2{x} feat(pricing): yearly toggle
{y}9b03f71{x} fix(docs): hydration warning in Toc
{y}5d2e8aa{x} chore: bump next to 15.4
{y}c77f310{x} feat(checkout): saved cards
{y}12ab9d4{x} fix(auth): refresh token race
{y}e09f5c1{x} refactor: plan data in plans.json
EOF

# Show a transcript in a pane: clear the typed command, print, then hold without a prompt.
show() { h pane run "$1" "clear; cat $ROOT/transcripts/$2.txt; stty -echo; sleep 999999" >/dev/null; }

workspace() { # label, project dir -> root pane id
  h workspace create --cwd "$ROOT/$2" --label "$1" | jq -r '.result.root_pane.pane_id'
}
tab() { # workspace id, project dir -> pane id
  h tab create --workspace "$1" --cwd "$ROOT/$2" | jq -r '.result.root_pane.pane_id'
}
agent() { # pane, agent kind, state, title, transcript
  h pane rename "$1" "$4" >/dev/null
  h pane report-agent --source paca-demo --agent "$2" --state "$3" "$1" >/dev/null
  show "$1" "$5"
}
# "done" is herdr's state for an agent that went idle in a background tab.
finished() { # pane, agent kind, title, transcript
  h pane rename "$1" "$3" >/dev/null
  h pane report-agent --source paca-demo --agent "$2" --state working "$1" >/dev/null
  h pane report-agent --source paca-demo --agent "$2" --state idle "$1" >/dev/null
  show "$1" "$4"
}

web=$(workspace lumen-web lumen-web); w1=${web%%:*}
ledger=$(workspace ledger-api ledger-api); w2=${ledger%%:*}
ios=$(workspace orbit-ios orbit-ios); w3=${ios%%:*}
infra=$(workspace infra infra); w4=${infra%%:*}

agent "$web" claude working "Redesign pricing page" pricing
finished "$(tab "$w1" lumen-web)" codex "Fix hydration warning on /docs" hydration
dev=$(tab "$w1" lumen-web); h pane rename "$dev" "dev server" >/dev/null; show "$dev" devserver
gitlog=$(tab "$w1" lumen-web); show "$gitlog" gitlog

agent "$ledger" claude blocked "Add idempotency keys to payments" idempotency
agent "$(tab "$w2" ledger-api)" gemini working "Integration tests for refunds" refunds

agent "$ios" cursor idle "Migrate settings to SwiftUI" settings

agent "$infra" opencode working "Bump Terraform providers" terraform
finished "$(tab "$w4" infra)" amp "Tune autoscaling alerts" alerts

# Leave lumen-web's first tab focused, so the other panes count as background.
h tab focus "$w1:t1" >/dev/null 2>&1 || true

echo "demo session $NAME ready:"
h pane list | jq -r '.result.panes[] | "  \(.pane_id)  \(.agent // "shell")  \(.agent_status)  \(.label // "")"'
