#!/bin/bash

# Source utility scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/scripts/utils/logger.sh"

# Set up error handling
set -euo pipefail
trap 'handle_error "$?" "$LINENO" "$BASH_LINENO" "$BASH_COMMAND" "$(printf "::%s" "${FUNCNAME[@]:-}")"' ERR

# Error handler
handle_error() {
    local exit_code="$1"
    local line_no="$2"
    local bash_lineno="$3"
    local last_command="$4"
    local error_trace="$5"
    
    log_error "Error occurred in ${BASH_SOURCE[1]}:${line_no}"
    log_error "Last command: ${last_command}"
    log_error "Exit code: ${exit_code}"
    log_error "Error trace: ${error_trace}"
    
    exit "${exit_code}"
}

# Define clusters to clean up
CLUSTERS=("dev" "staging" "prod")

# Function to delete a single cluster
delete_cluster() {
    local cluster_name="$1"
    local force="${2:-false}"
    
    log_info "Deleting cluster: $cluster_name"
    
    # Check if cluster exists
    if ! k3d cluster list | grep -q "$cluster_name"; then
        log_warn "Cluster $cluster_name not found, skipping..."
        return 0
    fi
    
    # Try to delete the cluster gracefully first
    if ! log_cmd "k3d cluster delete \"$cluster_name\""; then
        if [ "$force" = true ]; then
            log_warn "Graceful deletion failed, forcing deletion..."
            if ! log_cmd "k3d cluster delete \"$cluster_name\" --force"; then
                log_error "Force deletion of cluster $cluster_name failed"
                return 1
            fi
        else
            log_error "Failed to delete cluster $cluster_name"
            return 1
        fi
    fi
    
    # Remove the kubeconfig file
    if [ -f "$HOME/.k3d/kubeconfig-$cluster_name.yaml" ]; then
        if ! log_cmd "rm -f \"$HOME/.k3d/kubeconfig-$cluster_name.yaml\""; then
            log_warn "Failed to remove kubeconfig file for $cluster_name"
        fi
    fi
    
    log_info "Cluster $cluster_name deleted successfully"
    log_info "-----------------------------------"
    return 0
}

# Function to clean up Docker resources
cleanup_docker_resources() {
    log_info "Cleaning up Docker resources..."
    
    # Remove k3d containers
    local containers
    containers="$(docker ps -a | grep 'k3d' | awk '{print $1}' || true)"
    if [ -n "$containers" ]; then
        if ! log_cmd "docker rm -f $containers"; then
            log_warn "Failed to remove some k3d containers"
        fi
    fi
    
    # Remove k3d volumes
    local volumes
    volumes="$(docker volume ls | grep 'k3d' | awk '{print $2}' || true)"
    if [ -n "$volumes" ]; then
        if ! log_cmd "docker volume rm $volumes"; then
            log_warn "Failed to remove some k3d volumes"
        fi
    fi
    
    log_info "Docker cleanup completed"
}

# Main execution
main() {
    log_info "Starting cluster cleanup process..."
    
    local force=false
    if [ "${1:-}" = "--force" ]; then
        force=true
        log_warn "Force deletion enabled"
    fi
    
    # Delete each cluster
    local failed=0
    local cluster
    for cluster in "${CLUSTERS[@]}"; do
        if ! delete_cluster "$cluster" "$force"; then
            failed=1
            log_error "Failed to delete cluster: $cluster"
        fi
    done
    
    # Clean up Docker resources
    cleanup_docker_resources
    
    # Clean up logs older than 7 days
    if [ -d "${LOG_DIR}" ]; then
        log_info "Cleaning up old log files..."
        find "${LOG_DIR}" -name "k8s-local-*.log" -mtime +7 -delete 2>/dev/null || true
    fi
    
    if [ "$failed" -eq 1 ]; then
        log_error "Some clusters failed to delete properly"
        exit 1
    fi
    
    log_info "All clusters have been cleaned up successfully!"
}

# Run main function
main "$@" 