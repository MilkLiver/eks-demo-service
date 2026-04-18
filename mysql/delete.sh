#!/bin/bash
set -e

NAMESPACE="${1:-asiayo}"

echo "=== Removing MySQL Primary/Secondary from namespace: ${NAMESPACE} ==="

echo "[1/5] Deleting StatefulSets..."
kubectl delete statefulset mysql-secondary mysql-primary -n "$NAMESPACE" --ignore-not-found --force

echo "[2/5] Deleting Services..."
kubectl delete -f service.yaml -n "$NAMESPACE" --ignore-not-found --force

echo "[3/5] Deleting ConfigMaps..."
kubectl delete configmap mysql-primary-config mysql-secondary-config mysql-replication-init -n "$NAMESPACE" --ignore-not-found --force

echo "[4/5] Deleting Secret..."
kubectl delete secret mysql-secret -n "$NAMESPACE" --ignore-not-found --force

echo "[5/5] Deleting PVCs..."
kubectl delete pvc -l app=mysql -n "$NAMESPACE" --ignore-not-found --force

echo "=== Removal completed ==="
