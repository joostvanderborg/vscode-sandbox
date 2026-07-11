# Devcontainer sandbox

Quickly launch a VS Code devcontainer with Claude Code, `.env`, and an arbitrary
set of project directories mounted under `/workspace`.

```sh
./start-sandbox.sh                 # fzf-pick repo(s) from ~/Developer
./start-sandbox.sh my-repo         # mount ~/Developer/my-repo
./start-sandbox.sh /abs/path       # mount an absolute path
./start-sandbox.sh my-repo --danger  # alias claude to --dangerously-skip-permissions
```

macOS only. The script runs a preflight that checks tools, creates first-run
files, and verifies the Docker socket, so most fresh-machine issues fail fast
with a fix instead of a cryptic error.

## One-time setup on a new machine

1. **Docker Desktop** — install it, then enable the default socket:
   **Settings → Advanced → "Allow the default Docker socket to be used
   (requires password)" → Apply & Restart.**

   Without this, `/var/run/docker.sock` never gets created. The `docker` CLI
   still works (it uses the `desktop-linux` context), but the VS Code Dev
   Containers extension connects to the *default* context at
   `/var/run/docker.sock` and fails with:

   ```
   failed to connect to the docker API at unix:///var/run/docker.sock ...
   dial unix /var/run/docker.sock: connect: no such file or directory
   ```

2. **Host tools:**

   ```sh
   brew install fzf jq
   npm install -g @devcontainers/cli
   ```

   Also install the VS Code `code` command: `Cmd+Shift+P` →
   *Shell Command: Install 'code' command in PATH*. (`xxd` ships with macOS.)

3. **First-run files** — `start-sandbox.sh` auto-creates these if missing, but
   they must exist before `devcontainer up`, or Docker's bind mounts fail:
   `.env`, `.bash_history`, and `.claude/`. `.env` and `.bash_history` are
   gitignored; `.claude/` is empty on a fresh clone.

The preflight verifies all of the above and stops with an actionable message if
anything is missing.
