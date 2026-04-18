#!/bin/bash
set -e

NAMESPACE="${1:-asiayo}"

echo "=== Removing Demo Service from namespace: ${NAMESPACE} ==="

echo "[1/4] Deleting Ingress..."
kubectl delete -f ingress.yaml -n "$NAMESPACE" --ignore-not-found --force

echo "[2/4] Deleting Deployment..."
kubectl delete -f deployment.yaml -n "$NAMESPACE" --ignore-not-found --force

echo "[3/4] Deleting Service..."
kubectl delete -f ../service.yaml -n "$NAMESPACE" --ignore-not-found --force

echo "[4/4] Deleting PVCs..."
kubectl delete \
  -f pvc-html.yaml \
  -f pvc-logs.yaml \
  -n "$NAMESPACE" --ignore-not-found --force

echo "=== Demo Service removal completed ==="
