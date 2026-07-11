#!/usr/bin/env zsh
set -euo pipefail

DEVCONTAINER_FOLDER="$HOME/Developer/devcontainer"
DEVCONTAINER_CONFIG="$DEVCONTAINER_FOLDER/.devcontainer/devcontainer.json"
DEVCONTAINER_CONFIG_BASE="$DEVCONTAINER_FOLDER/.devcontainer/devcontainer.base.json"
PROJECTS_FOLDER="$HOME/Developer"
WORKSPACE_FILE="$DEVCONTAINER_FOLDER/sandbox.code-workspace"

die()  { echo "[sandbox] ERROR: $*" >&2; exit 1; }
info() { echo "[sandbox] $*"; }

# Parse args — separate --danger flag from repo names
SKIP_PERMISSIONS=false
FILTERED_ARGS=()

for arg in "$@"; do
  if [[ "$arg" == "--danger" ]]; then
    SKIP_PERMISSIONS=true
  else
    FILTERED_ARGS+=("$arg")
  fi
done
set -- "${FILTERED_ARGS[@]}"

# Repo selection
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

# Create base config snapshot if it doesn't exist yet
if [ ! -f "$DEVCONTAINER_CONFIG_BASE" ]; then
  info "Creating base config snapshot..."
  cp "$DEVCONTAINER_CONFIG" "$DEVCONTAINER_CONFIG_BASE"
fi

# Remove existing container (stopped or running) so devcontainer up creates a fresh one
EXISTING=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep "vsc-devcontainer" || true)
if [ -n "$EXISTING" ]; then
  info "Removing existing container..."
  docker rm -f $EXISTING >/dev/null
fi

# Inject repo mounts into devcontainer.json
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

jq --argjson newmounts "$MOUNT_JSON" \
  '.mounts += $newmounts' \
  "$DEVCONTAINER_CONFIG_BASE" > "$DEVCONTAINER_CONFIG"

# Start the devcontainer — because the container was removed above, devcontainer up
# always runs docker build (with layer cache), so the image reflects the current
# Dockerfile and VS Code won't prompt for a rebuild on connect
info "Starting devcontainer..."
devcontainer up --workspace-folder "$DEVCONTAINER_FOLDER"

# Set up --dangerously-skip-permissions alias if requested
if [ "$SKIP_PERMISSIONS" = true ]; then
  info "Setting up 'claude' alias with --dangerously-skip-permissions..."
  devcontainer exec --workspace-folder "$DEVCONTAINER_FOLDER" \
    zsh -c 'grep -qF "dangerously-skip-permissions" /home/node/.zshrc \
      || echo "alias claude=\"claude --dangerously-skip-permissions\"" >> /home/node/.zshrc'
  info "Alias added. Open a new terminal in the container to use it."
fi

# Generate dynamic workspace file
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

# (Re)open VS Code — triggers reconnect/rebuild against the new container
info "Opening VS Code..."
code --remote "dev-container+$(printf '%s' "$DEVCONTAINER_FOLDER" | xxd -p | tr -d '\n')" \
  /devcontainer-config/sandbox.code-workspace

# Summary
info "Ready. Mounted repos:"
for repo in "${REPOS[@]}"; do
  echo "  /workspace/$(basename "$repo") → $repo"
done

if [ "$SKIP_PERMISSIONS" = true ]; then
  echo ""
  echo "  ⚠️  --dangerously-skip-permissions is active in this session."
fi
