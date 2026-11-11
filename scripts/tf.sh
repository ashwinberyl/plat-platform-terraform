#!/usr/bin/env bash
# Usage: scripts/tf.sh <stack> <terraform-command> [args...]
#   scripts/tf.sh 20-network plan
#   scripts/tf.sh 20-network apply -var enable_nat=true
#   scripts/tf.sh bootstrap migrate        # one-time: move local state into S3
# <stack> is "bootstrap", a directory name under stacks/, or labs/<name> for a lab that uses remote state.
set -euo pipefail

STACK="${1:?usage: tf.sh <stack> <command> [args...]}"
CMD="${2:?usage: tf.sh <stack> <command> [args...]}"
shift 2

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="${TF_STATE_BUCKET:-plat-tfstate-${ACCOUNT}-${REGION}}"

if [ "$STACK" = "bootstrap" ]; then
  DIR="$ROOT/bootstrap"
elif [[ "$STACK" == labs/* ]]; then
  DIR="$ROOT/$STACK"
else
  DIR="$ROOT/stacks/$STACK"
fi
[ -d "$DIR" ] || { echo "no such stack: $STACK" >&2; exit 1; }

BACKEND=(
  -backend-config="bucket=${BUCKET}"
  -backend-config="key=${STACK}/terraform.tfstate"
  -backend-config="region=${REGION}"
  -backend-config="use_lockfile=true"
  -backend-config="encrypt=true"
)

case "$CMD" in
  migrate)
    terraform -chdir="$DIR" init -migrate-state -force-copy -input=false "${BACKEND[@]}"
    ;;
  init)
    terraform -chdir="$DIR" init -input=false -reconfigure "${BACKEND[@]}" "$@"
    ;;
  *)
    terraform -chdir="$DIR" init -input=false -reconfigure "${BACKEND[@]}" > /dev/null
    terraform -chdir="$DIR" "$CMD" "$@"
    ;;
esac
