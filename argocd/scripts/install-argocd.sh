#!/bin/bash

# Source utility scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../scripts/utils/logger.sh"

# Set up error handling
set -euo pipefail

# Define clusters
CLUSTERS=("dev" "staging" "prod")
ARGOCD_VERSION="v2.9.3"  # Update this to the latest stable version

install_argocd() {
    local cluster_name="$1"
    local k3d_cluster="k3d-${cluster_name}"
    
    log_info "Installing ArgoCD on cluster: $cluster_name"
    
    # Switch context
    kubectl config use-context "$k3d_cluster"
    
    # Create namespace and apply initial configurations
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -f "${SCRIPT_DIR}/../base/argocd-install.yaml"
    
    # Apply core ArgoCD installation
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml
    
    # Wait for ArgoCD server to be ready
    log_info "Waiting for ArgoCD server to be ready..."
    kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
    
    log_info "ArgoCD installed successfully on $cluster_name"
}

main() {
    log_info "Starting ArgoCD installation across all clusters..."
    
    for cluster in "${CLUSTERS[@]}"; do
        if ! install_argocd "$cluster"; then
            log_error "Failed to install ArgoCD on cluster: $cluster"
            exit 1
        fi
    done
    
    log_info "ArgoCD installation completed successfully!"
}

# Run main function
main 