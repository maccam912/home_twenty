#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob
for directory in releases/*; do
    commit=$(basename "$directory")
    tag="build-$commit"
    # The tag is a full commit ID. Re-running a published build is a no-op.
    if draft=$(gh release view "$tag" --json isDraft --jq .isDraft); then
        if [[ "$draft" == false ]]; then
            continue
        fi
    else
        gh release create "$tag" --target "$commit" --draft --prerelease \
            --title "Home Twenty · ${commit:0:12}" \
            --notes "Playable builds of commit \`$commit\` for Android (ARM), Linux and Windows (x86-64), and macOS (Universal)."
    fi
    gh release upload "$tag" "$directory"/* --clobber
    gh release edit "$tag" --draft=false --prerelease
done
