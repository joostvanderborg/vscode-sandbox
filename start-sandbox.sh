#!/usr/bin/env zsh
set -euo pipefail

DEVCONTAINER_FOLDER="$HOME/Developer/devcontainer"
DEVCONTAINER_CONFIG="$DEVCONTAINER_FOLDER/.devcontainer/devcontainer.json"
DEVCONTAINER_CONFIG_BASE="$DEVCONTAINER_FOLDER/.devcontainer/devcontainer.base.json"
PROJECTS_FOLDER="$HOME/Developer"
# Only this folder is mounted into the container (read-only, at /devcontainer-config),
# so the agent can't read .env or edit scripts that run on the host.
WORKSPACE_DIR="$DEVCONTAINER_FOLDER/.workspace"
WORKSPACE_FILE="$WORKSPACE_DIR/sandbox.code-workspace"
VSCODE_USER_SETTINGS="$HOME/Library/Application Support/Code/User/settings.json"

die()  { echo "[sandbox] ERROR: $*" >&2; exit 1; }
info() { echo "[sandbox] $*"; }

# --- Preflight: make a fresh machine work without manual setup ---------------
preflight() {
  # Required host tools, with install hints
  local missing=0
  for tool in fzf jq xxd code devcontainer docker; do
    command -v "$tool" >/dev/null 2>&1 && continue
    missing=1
    case "$tool" in
      fzf|jq)        echo "[sandbox] MISSING: $tool  (brew install $tool)" >&2 ;;
      devcontainer)  echo "[sandbox] MISSING: devcontainer  (npm install -g @devcontainers/cli)" >&2 ;;
      code)          echo "[sandbox] MISSING: code  (VS Code → Cmd+Shift+P → 'Shell Command: Install code command in PATH')" >&2 ;;
      docker)        echo "[sandbox] MISSING: docker  (install Docker Desktop)" >&2 ;;
      xxd)           echo "[sandbox] MISSING: xxd  (install with Xcode command line tools: xcode-select --install)" >&2 ;;
    esac
  done
  [ "$missing" -eq 0 ] || die "Install the tools above and re-run."

  # First-run files that must exist before 'devcontainer up' or Docker's bind
  # mounts fail. .env and .bash_history are gitignored; .claude is empty on a
  # fresh clone. Create them if absent.
  [ -e "$DEVCONTAINER_FOLDER/.env" ]           || { info "Creating empty .env"; : > "$DEVCONTAINER_FOLDER/.env"; }
  [ -e "$DEVCONTAINER_FOLDER/.bash_history" ]  || { info "Creating .bash_history"; : > "$DEVCONTAINER_FOLDER/.bash_history"; }
  [ -d "$DEVCONTAINER_FOLDER/.claude" ]        || { info "Creating .claude/"; mkdir -p "$DEVCONTAINER_FOLDER/.claude"; }
  [ -d "$WORKSPACE_DIR" ]                      || mkdir -p "$WORKSPACE_DIR"

  # The Dev Containers extension forwards host git credentials unless these are
  # set in the host user settings (they are read by the host-side extension).
  # sandbox-scrub.sh still cleans up inside the container; this closes the source.
  local setting
  for setting in copyGitConfig gitCredentialHelperConfigLocation; do
    grep -Eq "\"dev\.containers\.$setting\"[[:space:]]*:[[:space:]]*(false|\"none\")" \
      "$VSCODE_USER_SETTINGS" 2>/dev/null && continue
    echo "[sandbox] WARNING: VS Code user settings lack \"dev.containers.$setting\" — host git credentials will be forwarded." >&2
    echo "[sandbox]          Add to $VSCODE_USER_SETTINGS:" >&2
    echo '[sandbox]            "dev.containers.copyGitConfig": false,' >&2
    echo '[sandbox]            "dev.containers.gitCredentialHelperConfigLocation": "none"' >&2
    break
  done

  # The VS Code Dev Containers extension connects to the default Docker context
  # at /var/run/docker.sock. Docker Desktop only creates that socket when
  # "Allow the default Docker socket to be used" is enabled — otherwise the CLI
  # works (via the desktop-linux context) but VS Code cannot start the container.
  if [ ! -S /var/run/docker.sock ]; then
    die "$(cat <<'EOF'
/var/run/docker.sock is missing — VS Code Dev Containers will fail to connect.
Enable it once in Docker Desktop:
  Settings → Advanced → "Allow the default Docker socket to be used (requires password)"
  → Apply & Restart.
(The docker CLI still works without this because it uses the desktop-linux context,
 but the VS Code extension needs the default socket.)
EOF
)"
  fi

  docker version >/dev/null 2>&1 || die "Docker daemon not reachable. Start Docker Desktop and retry."
}
preflight

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
