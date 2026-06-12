#!/usr/bin/env zsh
# start-sandbox.sh
# Start the Claude Code Sandbox devcontainer,
# mounting one or more project repos into /workspace.
# Always restarts the container fresh with the requested repos.

set -euo pipefail

DEVCONTAINER_FOLDER="$HOME/Developer/devcontainer"
DEVCONTAINER_CONFIG="$DEVCONTAINER_FOLDER/.devcontainer/devcontainer.json"
DEVCONTAINER_CONFIG_BASE="$DEVCONTAINER_FOLDER/.devcontainer/devcontainer.base.json"
PROJECTS_FOLDER="$HOME/Developer"
WORKSPACE_FILE="$DEVCONTAINER_FOLDER/sandbox.code-workspace"

# ─── Helpers ──────────────────────────────────────────────────────────────────

die()  { echo "[sandbox] ERROR: $*" >&2; exit 1; }
info() { echo "[sandbox] $*"; }

# ─── Resolve repos ────────────────────────────────────────────────────────────

REPOS=()

if [ "$#" -gt 0 ]; then
  for arg in "$@"; do
    if [[ "$arg" == /* ]]; then
      REPOS+=("$arg")
    else
      REPOS+=("$PROJECTS_FOLDER/$arg")
    fi
  done
else
  REPOS=("${(@f)$(
    find "$PROJECTS_FOLDER" -mindepth 1 -maxdepth 1 -type d \
      | grep -v "^${DEVCONTAINER_FOLDER}$" \
      | sort \
      | fzf --multi \
            --prompt="Select repo(s) > " \
            --header="TAB to select multiple, ENTER to confirm"
  )}")
  [ "${#REPOS[@]}" -gt 0 ] || die "No repos selected."
fi

for repo in "${REPOS[@]}"; do
  [ -d "$repo" ] || die "Folder not found: $repo"
done

# ─── Ensure base config exists ────────────────────────────────────────────────

# On first run, copy devcontainer.json to devcontainer.base.json
if [ ! -f "$DEVCONTAINER_CONFIG_BASE" ]; then
  info "Creating base config snapshot..."
  cp "$DEVCONTAINER_CONFIG" "$DEVCONTAINER_CONFIG_BASE"
fi

# ─── Stop running container if any ────────────────────────────────────────────

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "vsc-devcontainer"; then
  info "Stopping existing container..."
  docker stop $(docker ps --format '{{.Names}}' | grep "vsc-devcontainer") >/dev/null
fi

# ─── Inject repo mounts into devcontainer.json ────────────────────────────────

info "Configuring mounts..."

MOUNT_JSON="[]"
for repo in "${REPOS[@]}"; do
  name=$(basename "$repo")
  MOUNT_JSON=$(echo "$MOUNT_JSON" | jq \
    --arg src "$repo" \
    --arg dst "/workspace/$name" \
    '. += [{"source": $src, "target": $dst, "type": "bind"}]'
  )
  info "Mounting: $repo → /workspace/$name"
done

# Merge repo mounts into base config's mounts array
jq --argjson newmounts "$MOUNT_JSON" \
  '.mounts += $newmounts' \
  "$DEVCONTAINER_CONFIG_BASE" > "$DEVCONTAINER_CONFIG"

# ─── Start container ──────────────────────────────────────────────────────────

info "Starting devcontainer..."
devcontainer up --workspace-folder "$DEVCONTAINER_FOLDER"

# ─── Generate workspace file ──────────────────────────────────────────────────

info "Generating workspace file..."

FOLDERS_JSON=""
for repo in "${REPOS[@]}"; do
  name=$(basename "$repo")
  FOLDERS_JSON+="{\"path\": \"/workspace/$name\"},"
done
FOLDERS_JSON="${FOLDERS_JSON%,}"

cat > "$WORKSPACE_FILE" <<EOF
{
  "folders": [
    $FOLDERS_JSON
  ]
}
EOF

# ─── Open VS Code ─────────────────────────────────────────────────────────────

VSCODE_ALREADY_OPEN=false
if pgrep -x "Electron" >/dev/null 2>&1; then
  if lsof -c Electron 2>/dev/null | grep -q "$DEVCONTAINER_FOLDER"; then
    VSCODE_ALREADY_OPEN=true
  fi
fi

if [ "$VSCODE_ALREADY_OPEN" = true ]; then
  info "VS Code already open with this devcontainer — not reopening."
else
  info "Opening VS Code..."
  code --remote "dev-container+$(printf '%s' "$DEVCONTAINER_FOLDER" | xxd -p | tr -d '\n')" /devcontainer-config/sandbox.code-workspace
fi

# ─── Summary ──────────────────────────────────────────────────────────────────

info "Ready. Mounted repos:"
for repo in "${REPOS[@]}"; do
  echo "  /workspace/$(basename "$repo") → $repo"
done
