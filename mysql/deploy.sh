#!/bin/bash
set -e

NAMESPACE="${1:-default}"
TIMEOUT="120s"

echo "=== Deploying MySQL Primary/Secondary to namespace: ${NAMESPACE} ==="

echo "[1/5] Applying Secret..."
kubectl apply -f secret.yaml -n "$NAMESPACE"

echo "[2/5] Applying ConfigMaps..."
kubectl apply \
  -f configmap-primary.yaml \
  -f configmap-secondary.yaml \
  -f configmap-secondary-init.yaml \
  -n "$NAMESPACE"

echo "[3/5] Applying Services..."
kubectl apply -f service.yaml -n "$NAMESPACE"

echo "[4/5] Deploying Primary StatefulSet..."
kubectl apply -f statefulset-primary.yaml -n "$NAMESPACE"

echo "Waiting for mysql-primary-0 to be ready (timeout: ${TIMEOUT})..."
kubectl wait --for=condition=Ready pod/mysql-primary-0 -n "$NAMESPACE" --timeout="$TIMEOUT"

echo "[5/5] Deploying Secondary StatefulSet..."
kubectl apply -f statefulset-secondary.yaml -n "$NAMESPACE"

echo "Waiting for secondary pods to be ready..."
kubectl rollout status statefulset/mysql-secondary -n "$NAMESPACE" --timeout="$TIMEOUT"

echo "=== Deployment completed ==="
echo ""
echo "Connection info:"
echo "  Read/Write (Primary):  mysql-primary.${NAMESPACE}.svc.cluster.local:3306"
echo "  Read-Only  (Secondary): mysql-secondary.${NAMESPACE}.svc.cluster.local:3306"
