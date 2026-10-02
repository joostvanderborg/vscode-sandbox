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

4. **VS Code user settings** (host, `Cmd+Shift+P` → *Preferences: Open User
   Settings (JSON)*) — stop the Dev Containers extension from forwarding your
   host git credentials into containers:

   ```json
   "dev.containers.copyGitConfig": false,
   "dev.containers.gitCredentialHelperConfigLocation": "none"
   ```

The preflight verifies all of the above and stops with an actionable message if
anything is missing (the VS Code settings only produce a warning).

## Credential isolation

No auth from the host reaches the container except what you configure
explicitly:

- **`.env`** is the opt-in channel. `GH_TOKEN` there is the only GitHub
  credential: `gh` is git's credential helper, and `git@github.com:` remotes are
  rewritten to HTTPS, so its scope is the agent's ceiling.
- **`.claude/`** is mounted for the Claude login, settings and memory. It is
  shared and writable across all sandboxes.
- **`.workspace/`** (just the generated workspace file) is the only part of this
  repo mounted into the container, read-only. `.env` and the launcher scripts
  are not reachable.
- **SSH agent, GPG agent and VS Code's git credential forwarding** are removed
  on every attach by `sandbox-scrub.sh`. It then checks that none answer; if
  any does, VS Code reports the `postAttachCommand` as failed and every new zsh
  shows a `⚠ CREDENTIAL LEAK` banner.

VS Code's own IPC channel to the host remains, because attaching needs it.
