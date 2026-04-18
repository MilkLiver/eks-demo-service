#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NAMESPACE="${1:-asiayo}"

echo "=========================================="
echo " Delete All Services"
echo " Namespace: ${NAMESPACE}"
echo "=========================================="

echo ""
echo "[1/3] Removing MySQL..."
cd "$SCRIPT_DIR/mysql" && bash delete.sh "$NAMESPACE"

echo ""
echo "[2/3] Removing Demo Service..."
cd "$SCRIPT_DIR/demo-service" && bash delete.sh "$NAMESPACE"

echo ""
echo "[3/3] Deleting StorageClass..."
kubectl delete -f "$SCRIPT_DIR/storageclass/storageclass.yaml" --ignore-not-found

echo ""
echo "=========================================="
echo " All services removed!"
echo "=========================================="
echo ""
echo "Note: Namespace '${NAMESPACE}' was not deleted. To delete it, run:"
echo "  kubectl delete namespace ${NAMESPACE}"
