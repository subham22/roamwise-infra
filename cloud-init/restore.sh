#!/usr/bin/env bash
# Run in OCI Cloud Shell after provision.sh, with .env and roamwise.dump uploaded to ~.
# Copies them to roamwise-api and restores the database before the backend ever starts.
set -euo pipefail
source ~/roamwise-ips
SSH="ssh -i ~/.ssh/oracle -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"
SCP="scp -i ~/.ssh/oracle -o StrictHostKeyChecking=accept-new"
[ -f ~/.env ] && [ -f ~/roamwise.dump ] || { echo "Upload .env and roamwise.dump to Cloud Shell first"; exit 1; }

echo "Waiting for roamwise-api setup to finish..."
until $SSH ubuntu@$API_PUB 'test -f ~/SETUP_DONE' 2>/dev/null; do sleep 15; echo -n .; done; echo " ready"

$SCP ~/.env ubuntu@$API_PUB:~/secrets.env
$SCP ~/roamwise.dump ubuntu@$API_PUB:~/roamwise.dump

$SSH ubuntu@$API_PUB bash -s <<'REMOTE'
set -euo pipefail
cd ~/roamwise-infra
# add secrets once; keep the per-VM lines cloud-init wrote
grep -q '^DB_PASSWORD=' .env || cat ~/secrets.env >> .env
rm -f ~/secrets.env
docker compose up -d postgres
until docker compose exec -T postgres pg_isready -U postgres -d roamwise >/dev/null 2>&1; do sleep 2; done
if [ "$(docker compose exec -T postgres psql -U postgres -d roamwise -tAc "select to_regclass('public.guide') is not null")" = "t" ]; then
  echo "Database already restored, skipping"
else
  docker compose exec -T postgres pg_restore -U postgres -d roamwise --no-owner --no-privileges < ~/roamwise.dump
fi
echo "guides: $(docker compose exec -T postgres psql -U postgres -d roamwise -tAc 'select count(*) from guide')"
echo "users:  $(docker compose exec -T postgres psql -U postgres -d roamwise -tAc 'select count(*) from users' 2>/dev/null || echo '?')"
REMOTE

echo "Waiting for roamwise-app setup to finish..."
until $SSH ubuntu@$APP_PUB 'test -f ~/SETUP_DONE' 2>/dev/null; do sleep 15; echo -n .; done; echo " ready"
echo "Both VMs ready. Database restored."
