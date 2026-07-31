#!/bin/bash
# ==============================================================================
# Istio Multi-Cluster Setup Script
# Configures multi-primary mesh across GCP and AWS clusters
# ==============================================================================

set -euo pipefail

# Configuration
GCP_CLUSTER_NAME="finflow-prod-gke"
GCP_CONTEXT="gke_finflow-prod_us-central1_finflow-prod-gke"
AWS_CLUSTER_NAME="finflow-prod-eks"
AWS_CONTEXT="arn:aws:eks:us-east-1:ACCOUNT_ID:cluster/finflow-prod-eks"
MESH_ID="finflow-mesh"
ISTIO_VERSION="1.20.0"

echo "=== FinFlow Multi-Cluster Istio Setup ==="
echo "GCP Cluster: ${GCP_CLUSTER_NAME}"
echo "AWS Cluster: ${AWS_CLUSTER_NAME}"
echo ""

# Step 1: Install Istio on GCP primary cluster
echo "[1/6] Installing Istio on GCP cluster..."
kubectl config use-context "${GCP_CONTEXT}"
istioctl install -f istio/multi-cluster/gcp-primary-config.yaml --skip-confirmation

# Step 2: Install East-West gateway on GCP
echo "[2/6] Installing East-West gateway on GCP..."
kubectl apply -f istio/multi-cluster/gcp-primary-config.yaml

# Wait for gateway to get external IP
echo "Waiting for East-West gateway external IP..."
kubectl wait --for=condition=ready pod -l istio=eastwestgateway -n istio-system --timeout=120s

# Step 3: Install Istio on AWS secondary cluster
echo "[3/6] Installing Istio on AWS cluster..."
kubectl config use-context "${AWS_CONTEXT}"
istioctl install -f istio/multi-cluster/aws-secondary-config.yaml --skip-confirmation

# Step 4: Create remote secrets for cross-cluster discovery
echo "[4/6] Creating remote secrets..."

# Create secret for GCP cluster and apply to AWS cluster
kubectl config use-context "${GCP_CONTEXT}"
istioctl create-remote-secret --name="${GCP_CLUSTER_NAME}" | \
  kubectl apply -f - --context="${AWS_CONTEXT}"

# Create secret for AWS cluster and apply to GCP cluster
kubectl config use-context "${AWS_CONTEXT}"
istioctl create-remote-secret --name="${AWS_CLUSTER_NAME}" | \
  kubectl apply -f - --context="${GCP_CONTEXT}"

# Step 5: Verify cross-cluster connectivity
echo "[5/6] Verifying cross-cluster connectivity..."
kubectl config use-context "${GCP_CONTEXT}"
istioctl remote-clusters

# Step 6: Deploy cross-cluster gateway configurations
echo "[6/6] Applying cross-cluster traffic policies..."
kubectl config use-context "${GCP_CONTEXT}"
kubectl apply -f istio/multi-cluster/

kubectl config use-context "${AWS_CONTEXT}"
kubectl apply -f istio/multi-cluster/

echo ""
echo "=== Multi-cluster setup complete ==="
echo "Verify with: istioctl analyze --all-namespaces"
echo "Check endpoints: istioctl proxy-config endpoints <pod> | grep finflow"
