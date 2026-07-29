#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <version>" >&2
    exit 2
fi

version="${1#v}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$ ]]; then
    echo "invalid release version: $1" >&2
    exit 2
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist="$root/dist"
stage="$dist/stage"
source_date_epoch="${SOURCE_DATE_EPOCH:-$(git -C "$root" show -s --format=%ct HEAD)}"

if [[ -z "$root" || "$root" == "/" || "$dist" != "$root/dist" ]]; then
    echo "refusing to clean an unexpected output directory: $dist" >&2
    exit 1
fi

rm -rf -- "$dist"
mkdir -p "$stage"

targets=(
    "linux amd64"
    "linux arm64"
    "windows amd64"
    "windows arm64"
    "darwin amd64"
    "darwin arm64"
)

for target in "${targets[@]}"; do
    read -r goos goarch <<<"$target"
    archive_base="samp-plugin_${version}_${goos}_${goarch}"
    package_dir="$stage/$archive_base"
    executable="samp-plugin"
    if [[ "$goos" == "windows" ]]; then
        executable+=".exe"
    fi

    mkdir -p "$package_dir"
    cp "$root/LICENSE" "$package_dir/LICENSE"
    (
        cd "$root"
        CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" go build \
            -trimpath \
            -ldflags="-s -w -buildid= -X main.version=$version" \
            -o "$package_dir/$executable" \
            ./cmd/samp-plugin
    )
    touch -d "@$source_date_epoch" "$package_dir/$executable" "$package_dir/LICENSE"

    if [[ "$goos" == "windows" ]]; then
        (
            cd "$package_dir"
            zip -X -q "$dist/$archive_base.zip" LICENSE "$executable"
        )
    else
        tar \
            --sort=name \
            --mtime="@$source_date_epoch" \
            --owner=0 \
            --group=0 \
            --numeric-owner \
            -C "$package_dir" \
            -cf "$dist/$archive_base.tar" \
            LICENSE \
            "$executable"
        gzip -n "$dist/$archive_base.tar"
    fi
done

rm -rf -- "$stage"
(
    cd "$dist"
    sha256sum ./*.tar.gz ./*.zip > checksums.txt
)
