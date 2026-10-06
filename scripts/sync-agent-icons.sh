#!/usr/bin/env bash
# Copy agent logos from LobeHub Icons (github.com/lobehub/lobe-icons, MIT) into
# Sources/Paca/Resources/AgentIcons as agent-<herdr kind>.svg. Agents without a logo
# here show no icon in the sidebar.
#
#   scripts/sync-agent-icons.sh            latest @lobehub/icons-static-svg
#   scripts/sync-agent-icons.sh 1.95.1     a pinned version
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:-1.95.1}
# herdr agent kind -> LobeHub icon name.
AGENTS=(
  agy:antigravity amp:amp claude:claude cline:cline codex:codex copilot:githubcopilot
  cursor:cursor devin:devin gemini:gemini grok:grok hermes:nousresearch kilo:kilocode
  kimi:kimi kiro:kiro opencode:opencode qodercli:qoder qwen:qwen
)

OUT=Sources/Paca/Resources/AgentIcons
rm -rf "$OUT"
mkdir -p "$OUT"
for pair in "${AGENTS[@]}"; do
  kind=${pair%%:*} icon=${pair#*:}
  # Monochrome logos as template images. NSImage's SVG reader handles neither currentColor,
  # em sizes nor packed arc flags, so fix all three.
  curl -fsSL "https://cdn.jsdelivr.net/npm/@lobehub/icons-static-svg@$VERSION/icons/$icon.svg" \
    | sed -e 's/currentColor/#000/g' -e 's/="1em"/="24"/g' \
    | scripts/tools/svg-expand-arcs.py > "$OUT/agent-$kind.svg"
done
echo "agent icons synced: ${#AGENTS[@]} in $OUT"
