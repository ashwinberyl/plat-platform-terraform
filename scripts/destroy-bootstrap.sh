#!/usr/bin/env bash
# The last step of a full teardown: remove the state bucket and the CI roles.
#
# The bootstrap stack keeps its OWN state in the bucket it creates, and the bucket has prevent_destroy,
# so removing it takes four deliberate steps. This script does them, after you type the account id.
#   1. check that no other stack still has resources in state
#   2. move bootstrap's state from S3 back to a local file
#   3. turn prevent_destroy off (in your working copy only) and empty every object AND every version
#   4. terraform destroy
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGION="${AWS_REGION:-us-east-1}"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="plat-tfstate-${ACCOUNT}-${REGION}"

read -r -p "This deletes bucket ${BUCKET} and the CI roles. Type the account id (${ACCOUNT}) to continue: " answer
[ "$answer" = "$ACCOUNT" ] || { echo "not confirmed"; exit 1; }

echo "== 1. other stacks must be destroyed first"
LEFT=$(aws s3api list-objects-v2 --bucket "$BUCKET" --query "Contents[?ends_with(Key, 'terraform.tfstate') && !starts_with(Key, 'bootstrap/')].[Key,Size]" --output text || true)
# A destroyed stack leaves a tiny state file (no resources). Anything larger still tracks something.
BIG=$(echo "$LEFT" | awk 'NF==2 && $2 > 500 {print $1}')
if [ -n "$BIG" ]; then
  echo "These stacks still have resources in state. Run 'make down' first:"; echo "$BIG"; exit 1
fi

echo "== 2. move bootstrap's state back to a local file"
rm -f "$ROOT/bootstrap/backend.tf"
terraform -chdir="$ROOT/bootstrap" init -migrate-state -force-copy -input=false

echo "== 3. allow the bucket to be destroyed, then empty it (all versions and delete markers)"
sed -i 's/prevent_destroy = true/prevent_destroy = false/' "$ROOT/bootstrap/main.tf"
while :; do
  aws s3api list-object-versions --bucket "$BUCKET" --max-items 1000 --output json \
    --query '{Objects: [Versions, DeleteMarkers][].{Key: Key, VersionId: VersionId}}' > /tmp/plat-delete-batch.json
  grep -q '"Key"' /tmp/plat-delete-batch.json || break
  aws s3api delete-objects --bucket "$BUCKET" --delete "file:///tmp/plat-delete-batch.json" --query 'length(Deleted)' --output text
done

echo "== 4. destroy"
terraform -chdir="$ROOT/bootstrap" destroy -auto-approve -input=false

echo "Done. 'git checkout bootstrap/main.tf' restores the prevent_destroy line."
