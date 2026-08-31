#!/usr/bin/env bash
# Sets up the Codion grounding materials: shallow-clones the framework source
# at the pinned release tag, plus the five standalone demo applications
# (which always track the latest release). Idempotent — re-run after a new
# Codion release (and a `git pull` of this repo) to refresh everything.
set -euo pipefail
cd "$(dirname "$0")"

# The Codion release these materials are pinned to. Bumped with each release,
# in lockstep with manual.md and the skill's version references.
CODION_VERSION="0.18.85"

DEMOS="petclinic world chinook llemmy sdkboy"
GITHUB="https://github.com/codion-is"

echo "Codion materials setup — pinned to v${CODION_VERSION}"
echo

# --- framework source at the release tag ------------------------------------
if [ -d codion ]; then
    current=$(git -C codion describe --tags 2>/dev/null || echo "unknown")
    if [ "${current}" = "v${CODION_VERSION}" ]; then
        echo "codion: already at v${CODION_VERSION}"
    else
        echo "codion: at ${current}, re-cloning at v${CODION_VERSION}"
        rm -rf codion
    fi
fi
if [ ! -d codion ]; then
    git clone --quiet --depth 1 --branch "v${CODION_VERSION}" "${GITHUB}/codion.git"
    echo "codion: cloned at v${CODION_VERSION}"
fi

# --- demo applications (default branch tracks the latest release) -----------
for demo in ${DEMOS}; do
    if [ -d "${demo}" ]; then
        git -C "${demo}" pull --quiet
        echo "${demo}: updated"
    else
        git clone --quiet --depth 1 "${GITHUB}/${demo}.git"
        echo "${demo}: cloned"
    fi
done

# --- verify the demos track the pinned release -------------------------------
echo
mismatch=0
for demo in ${DEMOS}; do
    version=$(grep -m1 -oP 'codion\s*=\s*"\K[^"]+' "${demo}/gradle/libs.versions.toml" 2>/dev/null || echo "?")
    if [ "${version}" = "${CODION_VERSION}" ]; then
        echo "${demo}: codion ${version} — OK"
    else
        echo "${demo}: codion ${version} — MISMATCH (expected ${CODION_VERSION})"
        mismatch=1
    fi
done

echo
if [ "${mismatch}" = "1" ]; then
    echo "Version mismatch detected — a release is likely in progress."
    echo "Re-run this script once all demos are on ${CODION_VERSION}, or check"
    echo "for a newer version of this repository."
    exit 1
fi
echo "Done. See README.md — to make the skill available to Claude Code:"
echo "  ln -s \"\$(pwd)/skills/codion\" ~/.claude/skills/codion"
