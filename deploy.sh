#!/bin/bash
# deploy.sh - run Terraform for ONE environment, chosen by argument.
# Usage: ./deploy.sh <dev|test|prod> <init|plan|apply|destroy|output|validate> [extra terraform args]
# Example: ./deploy.sh dev apply
#          ./deploy.sh dev plan -var="asg_max_size=4"

set -e

ENVIRONMENT="$1"
ACTION="$2"
shift 2 || true

case "$ENVIRONMENT" in
  dev|test|prod) ;;
  *) echo "Usage: $0 <dev|test|prod> <init|plan|apply|destroy|output|validate> [terraform args]"; exit 1 ;;
esac

case "$ACTION" in
  init|plan|apply|destroy|output|validate) ;;
  *) echo "Unknown action '$ACTION'. Use: init, plan, apply, destroy, output or validate"; exit 1 ;;
esac

DIR="$(cd "$(dirname "$0")" && pwd)/environments/$ENVIRONMENT"
cd "$DIR"
echo "=== Environment: $ENVIRONMENT | Action: $ACTION | Dir: $DIR ==="

# Make sure providers/modules are initialised before any other action
if [ "$ACTION" != "init" ] && [ ! -d .terraform ]; then
  terraform init
fi

terraform "$ACTION" "$@"
