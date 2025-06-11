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

# Define clusters
CLUSTERS=("dev" "staging" "prod")

# Function to apply configurations to a cluster
apply_cluster_config() {
    local cluster_name="$1"

    log_info "Applying configurations for cluster: $cluster_name"

    # Switch to the appropriate context
    if ! log_cmd "kubectl config use-context \"$cluster_name\""; then
        log_error "Failed to switch to context $cluster_name"
        return 1
    fi

    # Create ingress-nginx namespace if it doesn't exist
    if ! log_cmd "kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -"; then
        log_error "Failed to create/verify ingress-nginx namespace"
        return 1
    fi

    # Apply network configurations
    log_info "Applying network configurations..."
    if ! log_cmd "kubectl apply -f \"${SCRIPT_DIR}/cluster-configs/$cluster_name/network/\""; then
        log_error "Failed to apply network configurations"
        return 1
    fi

    # Create default namespace if it doesn't exist
    if ! log_cmd "kubectl create namespace default --dry-run=client -o yaml | kubectl apply -f -"; then
        log_error "Failed to create/verify default namespace"
        return 1
    fi

    # Apply resource limits
    log_info "Applying resource limits..."
    if ! log_cmd "kubectl apply -f \"${SCRIPT_DIR}/cluster-configs/$cluster_name/resources/\""; then
        log_error "Failed to apply resource limits"
        return 1
    fi

    log_info "Configuration applied successfully for $cluster_name cluster"
    log_info "-----------------------------------"
    return 0
}

# Function to verify cluster exists and is accessible
verify_cluster() {
    local cluster_name="$1"

    if ! kubectl config get-contexts "$cluster_name" &>/dev/null; then
        log_error "Cluster context $cluster_name not found"
        return 1
    fi

    if ! kubectl --context "$cluster_name" get nodes &>/dev/null; then
        log_error "Cannot access cluster $cluster_name"
        return 1
    fi

    return 0
}

# Main execution
main() {
    log_info "Starting configuration application process..."

    # Verify all clusters exist before proceeding
    local cluster
    for cluster in "${CLUSTERS[@]}"; do
        if ! verify_cluster "$cluster"; then
            log_fatal "Cluster verification failed. Please ensure all clusters are created and accessible."
        fi
    done

    # Apply configurations to each cluster
    local failed=0
    for cluster in "${CLUSTERS[@]}"; do
        if ! apply_cluster_config "$cluster"; then
            failed=1
            log_error "Failed to apply configurations to cluster: $cluster"
        fi
    done

    if [ "$failed" -eq 1 ]; then
        log_error "Some configurations failed to apply"
        exit 1
    fi

    log_info "All configurations have been applied successfully!"
}

# Run main function
main