#!/usr/bin/env bash
# Prepare host directories for the Forgejo Actions runner.
# The runner container runs as UID/GID 1000 and must be able to write to the
# bind-mounted /data volume (state: registration + workspace + cache), and dind
# needs a persistent /var/lib/docker volume for its image cache.
#
# This creates/chowns the host-side paths that compose bind-mounts, i.e. the
# ones under ${DOCKER_VOLUME_STORAGE}/forgejo/runner (default: /srv/appdata).
#
# Run ONCE on the target LXC (lxc-devops), e.g.:
#     ssh lxc-devops
#     bash <(curl -s ...)   # or copy this script over and run it
#
# Then deploy the stack (Komodo redeploy or docker compose up -d).

set -euo pipefail

# Match ${DOCKER_VOLUME_STORAGE} set in stacks.toml for the forgejo stack.
VOLUME_STORAGE="${DOCKER_VOLUME_STORAGE:-/srv/appdata}"
RUNNER_UID="${RUNNER_UID:-1000}"
RUNNER_GID="${RUNNER_GID:-1000}"

BASE="$VOLUME_STORAGE/forgejo/runner"

mkdir -p "$BASE/data/.runner" "$BASE/data/workspace" "$BASE/data/.cache"
mkdir -p "$BASE/dind"

chown -R "$RUNNER_UID:$RUNNER_GID" "$BASE/data"
chmod -R 775 "$BASE/data"

echo "Runner dirs ready under $BASE"
echo "  uid/gid: ${RUNNER_UID}:${RUNNER_GID}"
find "$BASE" -maxdepth 2 -type d | sort