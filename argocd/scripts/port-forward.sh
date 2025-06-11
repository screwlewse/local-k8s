#!/bin/bash

# Source utility scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../scripts/utils/logger.sh"

# Set up error handling
set -euo pipefail

# Default values
CLUSTER=${1:-"dev"}
NAMESPACE="argocd"
PORT="8080"

start_port_forward() {
    local k3d_cluster="k3d-${CLUSTER}"
    log_info "Starting port forward for ArgoCD UI on cluster: $CLUSTER"
    log_info "UI will be available at: http://localhost:$PORT"
    
    # Check if port forward is already running
    if pgrep -f "kubectl port-forward.*$PORT:443" > /dev/null; then
        log_error "Port forward already running on port $PORT"
        log_info "To kill existing port forward: pkill -f 'kubectl port-forward.*$PORT:443'"
        exit 1
    fi
    
    # Switch context
    kubectl config use-context "$k3d_cluster"
    
    # Start port forward
    kubectl port-forward -n "$NAMESPACE" svc/argocd-server "$PORT":443 &
    
    # Store PID
    echo $! > "/tmp/argocd-port-forward.pid"
    
    log_info "Port forward started. Press Ctrl+C to stop"
    log_info "Initial admin password can be retrieved with:"
    log_info "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d"
    
    # Wait for port forward to exit
    wait $!
}

cleanup() {
    log_info "Stopping port forward..."
    if [ -f "/tmp/argocd-port-forward.pid" ]; then
        kill $(cat "/tmp/argocd-port-forward.pid") 2>/dev/null || true
        rm "/tmp/argocd-port-forward.pid"
    fi
}

# Set up trap for cleanup
trap cleanup EXIT INT TERM

# Start port forward
start_port_forward 