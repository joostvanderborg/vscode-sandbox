#!/bin/bash
# Removes host credential channels that VS Code forwards into the container,
# then verifies none remain. Runs on every attach (postAttachCommand) because
# VS Code recreates the forwarding on each connect. GH_TOKEN from .env is the
# only intended credential and is excluded from the checks.
#
# Do not touch /tmp/vscode-remote-containers-*.js: the -server- file is VS Code's
# in-container server, and the helper is just a client for the IPC socket, so
# stubbing it breaks VS Code and hides leaks from the check below. Unlinking the
# IPC socket is what closes the channel: the server keeps running, but nothing
# can connect to it any more.
set -uo pipefail

STATUS_FILE=/tmp/sandbox-credential-leaks

# 1. Forwarded SSH agent, GPG agent and remote-containers IPC sockets. The IPC
#    socket is how the credential helper reaches the host keychain; the
#    dev.containers.* host settings only stop VS Code from configuring git to use it.
rm -f /tmp/vscode-ssh-auth-*.sock /tmp/vscode-remote-containers-ipc-*.sock
find "$HOME/.gnupg" -maxdepth 1 -type s -name 'S.gpg-agent*' -delete 2>/dev/null

# 2. Credential helper VS Code injects into ~/.gitconfig (gh's helper lives in /etc/gitconfig)
git config --global --unset-all credential.helper 2>/dev/null

# 3. Verify
leaks=()
github_query=$'protocol=https\nhost=github.com\n\n'

for sock in $(printf '%s\n' /tmp/vscode-ssh-auth-*.sock "${SSH_AUTH_SOCK:-}" | sort -u); do
  [ -S "$sock" ] && SSH_AUTH_SOCK="$sock" ssh-add -l >/dev/null 2>&1 \
    && leaks+=("SSH agent with keys at $sock")
done

# Output is captured before grepping: with pipefail, grep -q exiting early
# SIGPIPEs the producer and makes the pipeline report failure.
out=$(printf '%s' "$github_query" \
  | env -u GH_TOKEN -u GITHUB_TOKEN GIT_TERMINAL_PROMPT=0 GIT_ASKPASS= SSH_ASKPASS= \
    git credential fill 2>/dev/null)
grep -q '^password=' <<<"$out" && leaks+=("git returns a github.com credential that is not GH_TOKEN")

for js in /tmp/vscode-remote-containers-*.js; do
  [ -f "$js" ] || continue
  [[ "$js" == *-server-* ]] && continue
  out=$(printf '%s' "$github_query" | timeout 5 node "$js" git-credential-helper get 2>/dev/null)
  grep -q '^password=' <<<"$out" && leaks+=("VS Code credential helper answers via $js")
done

if [ "${#leaks[@]}" -gt 0 ]; then
  printf '%s\n' "${leaks[@]}" > "$STATUS_FILE"
  echo "⚠ CREDENTIAL LEAK: host credentials are reachable in this sandbox:" >&2
  printf '  - %s\n' "${leaks[@]}" >&2
  exit 1
fi

rm -f "$STATUS_FILE"
echo "[sandbox] No host credentials reachable."
