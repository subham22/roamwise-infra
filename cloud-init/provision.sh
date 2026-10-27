#!/usr/bin/env bash
# Run in OCI Cloud Shell: creates roamwise-api, then roamwise-app (wired to api's private IP).
set -euo pipefail
T="$OCI_TENANCY"
SHAPE=VM.Standard.E2.1.Micro
BASE=https://raw.githubusercontent.com/subham22/roamwise-infra/oracle-migration/cloud-init

[ -f ~/.ssh/oracle.pub ] || ssh-keygen -t rsa -b 4096 -f ~/.ssh/oracle -N "" -q
SUBNET=$(oci network subnet list --compartment-id "$T" --all \
  --query 'data[?"display-name"==`public subnet-roamwise`].id | [0]' --raw-output)
AD=$(oci iam availability-domain list --compartment-id "$T" --query 'data[0].name' --raw-output)
IMG=$(oci compute image list --compartment-id "$T" --operating-system "Canonical Ubuntu" \
  --operating-system-version "24.04" --shape $SHAPE --sort-by TIMECREATED --sort-order DESC \
  --query 'data[0].id' --raw-output)
echo "subnet=$SUBNET"; echo "image=$IMG"

instance() {  # existing RUNNING instance id, or launch a new one
  local id
  id=$(oci compute instance list --compartment-id "$T" --display-name "$1" --lifecycle-state RUNNING \
    --query 'data[0].id' --raw-output 2>/dev/null || true)
  if [ -z "$id" ] || [ "$id" = "None" ]; then
    id=$(oci compute instance launch --compartment-id "$T" --availability-domain "$AD" --shape $SHAPE \
      --image-id "$IMG" --subnet-id "$SUBNET" --assign-public-ip true --display-name "$1" \
      --boot-volume-size-in-gbs 50 --ssh-authorized-keys-file ~/.ssh/oracle.pub --user-data-file "$2" \
      --wait-for-state RUNNING --query 'data.id' --raw-output 2>/dev/null)
  fi
  echo "$id"
}
vnic() { oci compute instance list-vnics --instance-id "$1" --query "data[0].\"$2\"" --raw-output; }

curl -fsSL $BASE/api.sh -o /tmp/api.sh
API=$(instance roamwise-api /tmp/api.sh)
API_PRIV=$(vnic "$API" private-ip); API_PUB=$(vnic "$API" public-ip)

curl -fsSL $BASE/app.sh | sed "s/API_PRIVATE_IP/$API_PRIV/" > /tmp/app.sh
APP=$(instance roamwise-app /tmp/app.sh)
APP_PUB=$(vnic "$APP" public-ip)

printf 'API_PRIV=%s\nAPI_PUB=%s\nAPP_PUB=%s\n' "$API_PRIV" "$API_PUB" "$APP_PUB" | tee ~/roamwise-ips
