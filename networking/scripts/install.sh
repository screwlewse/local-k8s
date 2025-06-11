#!/bin/bash

# Source utility scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../scripts/utils/logger.sh"

# Set up error handling
set -euo pipefail

# Configuration
MAX_RETRIES=30
RETRY_INTERVAL=10

# Function to check if a namespace exists and is active
check_namespace() {
    local namespace="$1"
    kubectl get namespace "$namespace" -o json | grep -q '"phase":"Active"' 2>/dev/null
}

# Function to wait for namespace deletion
wait_for_namespace_deletion() {
    local namespace="$1"
    local retries=0
    
    while kubectl get namespace "$namespace" >/dev/null 2>&1; do
        if [ $retries -ge $MAX_RETRIES ]; then
            log_error "Timeout waiting for namespace $namespace to be deleted"
            return 1
        fi
        log_info "Waiting for namespace $namespace to be deleted... ($(($retries + 1))/$MAX_RETRIES)"
        sleep $RETRY_INTERVAL
        ((retries++))
    done
}

# Function to wait for pod readiness with timeout
wait_for_pod_ready() {
    local namespace="$1"
    local label="$2"
    local retries=0
    
    while true; do
        if [ $retries -ge $MAX_RETRIES ]; then
            log_error "Timeout waiting for pod with label $label in namespace $namespace"
            return 1
        fi
        
        local pod_status
        pod_status=$(kubectl get pods -n "$namespace" -l "$label" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
        
        if [ "$pod_status" = "Running" ]; then
            local ready_status
            ready_status=$(kubectl get pods -n "$namespace" -l "$label" -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
            
            if [ "$ready_status" = "true" ]; then
                log_info "Pod is ready!"
                return 0
            fi
        fi
        
        if [ "$pod_status" = "NotFound" ]; then
            log_info "Waiting for pod to be created... ($(($retries + 1))/$MAX_RETRIES)"
        else
            log_info "Pod status: $pod_status ($(($retries + 1))/$MAX_RETRIES)"
            
            # Check for pod errors
            local pod_name
            pod_name=$(kubectl get pods -n "$namespace" -l "$label" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
            if [ -n "$pod_name" ]; then
                kubectl describe pod -n "$namespace" "$pod_name" | grep -A 5 "Events:" || true
            fi
        fi
        
        sleep $RETRY_INTERVAL
        ((retries++))
    done
}

# Function to clean up existing installation
cleanup_existing() {
    log_info "Cleaning up any existing installation..."
    
    # Delete existing resources
    kubectl delete -f "$base_dir/base/nginx-ingress-controller.yaml" --wait=false 2>/dev/null || true
    
    # Wait for namespace deletion if it exists
    if kubectl get namespace ingress-nginx >/dev/null 2>&1; then
        wait_for_namespace_deletion "ingress-nginx"
    fi
}

# Main installation function
install_networking() {
    local base_dir="${SCRIPT_DIR}/.."
    
    # 1. Clean up existing installation
    cleanup_existing
    
    # 2. Install NGINX Ingress Controller
    log_info "Installing NGINX Ingress Controller..."
    kubectl apply -f "$base_dir/base/nginx-ingress-controller.yaml"
    
    # 3. Wait for the ingress controller to be ready
    log_info "Waiting for NGINX Ingress Controller to be ready..."
    if ! wait_for_pod_ready "ingress-nginx" "app.kubernetes.io/name=ingress-nginx"; then
        log_error "Failed to start NGINX Ingress Controller"
        log_info "Checking pod logs..."
        kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=50 || true
        return 1
    fi
    
    # 4. Install cert-manager
    log_info "Installing cert-manager..."
    kubectl apply -f "$base_dir/base/cert-manager.yaml"
    
    # 5. Wait for cert-manager to be ready
    log_info "Waiting for cert-manager to be ready..."
    if ! wait_for_pod_ready "cert-manager" "app.kubernetes.io/name=cert-manager"; then
        log_error "Failed to start cert-manager"
        return 1
    fi
    
    # 6. Install SSL certificates
    log_info "Installing SSL certificates..."
    kubectl apply -f "$base_dir/base/ssl-cert.yaml"
    
    # 7. Update hosts file
    log_info "Updating hosts file..."
    "$SCRIPT_DIR/update-hosts.sh"
    
    log_info "Installation completed successfully!"
    log_info "You can now access your services using the following domains:"
    log_info "- https://argocd.dev.local"
    log_info "- https://app.dev.local"
    log_info "- https://api.dev.local"
    log_info ""
    log_info "For more information, check the documentation in networking/docs/README.md"
}

# Run main installation
install_networking 