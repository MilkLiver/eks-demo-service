#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NAMESPACE="${1:-asiayo}"

echo "=========================================="
echo " Deploy All Services"
echo " Namespace: ${NAMESPACE}"
echo "=========================================="

echo ""
echo "[1/4] Creating namespace '${NAMESPACE}'..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "[2/4] Applying StorageClass..."
kubectl apply -f "$SCRIPT_DIR/storageclass/storageclass.yaml"

echo ""
echo "[3/4] Deploying Demo Service..."
cd "$SCRIPT_DIR/demo-service" && bash deploy.sh "$NAMESPACE"

echo ""
echo "[4/4] Deploying MySQL..."
cd "$SCRIPT_DIR/mysql" && bash deploy.sh "$NAMESPACE"

echo ""
echo "=========================================="
echo " All services deployed successfully!"
echo "=========================================="
