#!/bin/bash
set -e

SRC="Builds"
OUT="Builds/zip"

mkdir -p "$OUT"
cp "$SRC/GaasRoads.html" "$SRC/index.html"

cd "$SRC"
zip -r "zip/gaasroads-web.zip" \
    index.html \
    GaasRoads.* \
    -x "zip/*"

echo "Created $OUT/gaasroads-web.zip"
