#!/usr/bin/env bash
# Nightly Postgres dump on the api VM (cron, installed by the backend deploy). Keeps 7 days.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p ~/backups
f=~/backups/roamwise-$(date +%F).dump
docker compose exec -T postgres pg_dump -Fc -U postgres roamwise </dev/null > "$f.tmp"
[ -s "$f.tmp" ] || { echo "$(date) empty dump, keeping previous backups"; rm -f "$f.tmp"; exit 1; }
mv "$f.tmp" "$f"
find ~/backups -name 'roamwise-*.dump' -mtime +7 -delete
echo "$(date) backup ok: $f ($(du -h "$f" | cut -f1))"
