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

# Allow app VM -> api VM on 8080 (inside the VCN only). Appends to existing rules, never replaces them.
SL=$(oci network subnet get --subnet-id "$SUBNET" --query 'data."security-list-ids"[0]' --raw-output)
oci network security-list get --security-list-id "$SL" --query 'data."ingress-security-rules"' > /tmp/in.json
if jq -e 'any(.[]; ."tcp-options"."destination-port-range".min == 8080)' /tmp/in.json >/dev/null; then
  echo "8080 rule already present"
else
  jq 'def camel: gsub("-(?<c>[a-z])"; .c | ascii_upcase);
      walk(if type == "object" then with_entries(.key |= camel) else . end) | del(..|nulls)
      + [{"source":"10.0.0.0/16","sourceType":"CIDR_BLOCK","protocol":"6","isStateless":false,
          "tcpOptions":{"destinationPortRange":{"min":8080,"max":8080}},"description":"app VM to api VM"}]' \
    /tmp/in.json > /tmp/new.json
  # safety: same rules plus one, and every port-restricted rule kept its ports
  [ "$(jq length /tmp/new.json)" -eq $(( $(jq length /tmp/in.json) + 1 )) ] || { echo "rule merge looks wrong, not updating"; exit 1; }
  [ "$(jq '[.[]|select(."tcp-options")]|length' /tmp/in.json)" -eq $(( $(jq "[.[]|select(.tcpOptions)]|length" /tmp/new.json) - 1 )) ] || \
    { echo "port options lost, not updating"; exit 1; }
  oci network security-list update --security-list-id "$SL" --ingress-security-rules file:///tmp/new.json --force >/dev/null
  echo "8080 rule added"
fi

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
