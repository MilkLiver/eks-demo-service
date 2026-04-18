#!/bin/bash
set -e

NAMESPACE="${1:-asiayo}"
TIMEOUT="300s"

echo "=== Deploying Demo Service to namespace: ${NAMESPACE} ==="

echo "[1/4] Applying PVCs..."
kubectl apply \
  -f pvc-html.yaml \
  -f pvc-logs.yaml \
  -n "$NAMESPACE"

echo "[2/4] Applying Service..."
kubectl apply -f service.yaml -n "$NAMESPACE"

echo "[3/4] Deploying Deployment..."
kubectl apply -f deployment.yaml -n "$NAMESPACE"

echo "Waiting for deployment to be ready (timeout: ${TIMEOUT})..."
kubectl rollout status deployment/nginx -n "$NAMESPACE" --timeout="$TIMEOUT"

echo "[4/4] Applying Ingress..."
kubectl apply -f ingress.yaml -n "$NAMESPACE"

echo "=== Demo Service deployment completed ==="
