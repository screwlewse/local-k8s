#!/bin/bash

# Source utility scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/scripts/utils/logger.sh"
source "${SCRIPT_DIR}/scripts/utils/checks.sh"

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
    
    # Cleanup on error
    cleanup_on_error
    exit "${exit_code}"
}

# Cleanup function
cleanup_on_error() {
    log_warn "Performing cleanup after error..."
    local cluster
    for cluster in "${CLUSTERS[@]}"; do
        if k3d cluster list | grep -q "$cluster"; then
            log_info "Cleaning up cluster: $cluster"
            k3d cluster delete "$cluster" || true
        fi
    done
}

# Define cluster configurations
CLUSTERS=("dev" "staging" "prod")

# Define worker nodes and port offsets for each environment
declare -a WORKER_NODES PORT_OFFSETS

# Initialize arrays (bash 3.2 compatible way)
WORKER_NODES=(1 1 2)  # dev, staging, prod
PORT_OFFSETS=(8000 9000 10000)  # dev, staging, prod

# Function to get worker count for cluster
get_worker_count() {
    local cluster_name="$1"
    local index=0
    case "$cluster_name" in
        "dev")     index=0 ;;
        "staging") index=1 ;;
        "prod")    index=2 ;;
        *)         echo "1"; return ;;
    esac
    echo "${WORKER_NODES[$index]}"
}

# Function to get port offset for cluster
get_port_offset() {
    local cluster_name="$1"
    local index=0
    case "$cluster_name" in
        "dev")     index=0 ;;
        "staging") index=1 ;;
        "prod")    index=2 ;;
        *)         echo "8000"; return ;;
    esac
    echo "${PORT_OFFSETS[$index]}"
}

# Function to validate cluster creation
validate_cluster() {
    local cluster_name="$1"
    local max_retries=30
    local retry_interval=10
    local retries=0
    local worker_count
    worker_count="$(get_worker_count "$cluster_name")"
    local expected_nodes="$((1 + worker_count))"
    local ready_nodes
    
    log_info "Validating cluster: $cluster_name"
    
    while [ "$retries" -lt "$max_retries" ]; do
        if kubectl --context "k3d-${cluster_name}" get nodes &>/dev/null; then
            ready_nodes="$(kubectl --context "k3d-${cluster_name}" get nodes --no-headers | grep -c "Ready" || echo "0")"
            if [ "$ready_nodes" -eq "$expected_nodes" ]; then
                log_info "Cluster $cluster_name is ready"
                return 0
            fi
        fi
        
        retries="$((retries + 1))"
        log_debug "Waiting for cluster $cluster_name to be ready (attempt $retries/$max_retries)"
        sleep "$retry_interval"
    done
    
    log_error "Timeout waiting for cluster $cluster_name to be ready"
    return 1
}

# Function to create a single cluster
create_cluster() {
    local cluster_name="$1"
    local worker_count
    local port_offset
    local kubeconfig_file="$HOME/.k3d/kubeconfig-$cluster_name.yaml"
    
    worker_count="$(get_worker_count "$cluster_name")"
    port_offset="$(get_port_offset "$cluster_name")"
    local http_port="$((port_offset + 80))"
    local https_port="$((port_offset + 443))"
    local argo_port="$((port_offset + 81))"
    
    log_info "Creating cluster: $cluster_name with $worker_count worker nodes"
    
    # Create cluster with worker nodes and port mappings
    if ! log_cmd "k3d cluster create \"$cluster_name\" \
        --servers 1 \
        --agents \"$worker_count\" \
        --port \"$http_port:80@loadbalancer\" \
        --port \"$https_port:443@loadbalancer\" \
        --port \"$argo_port:8080@loadbalancer\" \
        --k3s-arg \"--disable=traefik@server:0\" \
        --k3s-arg \"--kubelet-arg=eviction-hard=imagefs.available<1%,nodefs.available<1%@agent:0\" \
        --k3s-arg \"--kubelet-arg=eviction-minimum-reclaim=imagefs.available=1%,nodefs.available=1%@agent:0\" \
        --k3s-arg \"--kubelet-arg=eviction-hard=imagefs.available<1%,nodefs.available<1%@server:0\" \
        --k3s-arg \"--kubelet-arg=eviction-minimum-reclaim=imagefs.available=1%,nodefs.available=1%@server:0\" \
        --wait"; then
        log_error "Failed to create cluster $cluster_name"
        return 1
    fi

    # Validate cluster creation
    if ! validate_cluster "$cluster_name"; then
        log_error "Cluster validation failed for $cluster_name"
        return 1
    fi
    
    # Get the kubeconfig and save it
    if ! log_cmd "k3d kubeconfig get \"$cluster_name\" > \"$kubeconfig_file\""; then
        log_error "Failed to get kubeconfig for cluster $cluster_name"
        return 1
    fi
    
    # Merge the new kubeconfig with existing KUBECONFIG if it exists
    if [ -n "${KUBECONFIG:-}" ]; then
        log_info "Merging kubeconfig files..."
        local temp_kubeconfig
        temp_kubeconfig="$(mktemp)"
        
        # Export current KUBECONFIG to a temporary file
        KUBECONFIG="$KUBECONFIG:$kubeconfig_file" kubectl config view --flatten > "$temp_kubeconfig"
        
        # Replace KUBECONFIG with the merged file
        export KUBECONFIG="$temp_kubeconfig"
    else
        export KUBECONFIG="$kubeconfig_file"
    fi
    
    # Rename context for clarity
    if ! log_cmd "kubectl config rename-context \"k3d-$cluster_name\" \"$cluster_name\""; then
        log_warn "Failed to rename context for cluster $cluster_name"
    fi
    
    log_info "Cluster $cluster_name created successfully!"
    log_info "HTTP port: $http_port"
    log_info "HTTPS port: $https_port"
    log_info "ArgoCD port: $argo_port"
    log_info "-----------------------------------"
}

# Main execution
main() {
    log_info "Starting cluster creation process..."
    
    # Run system checks
    if ! run_all_checks; then
        log_fatal "System checks failed. Please fix the issues and try again."
    fi
    
    # Create directory for kubeconfig files if it doesn't exist
    mkdir -p "$HOME/.k3d"
    
    # Create each cluster
    local cluster
    for cluster in "${CLUSTERS[@]}"; do
        if ! create_cluster "$cluster"; then
            log_error "Failed to create cluster $cluster"
            cleanup_on_error
            exit 1
        fi
    done
    
    # Create final merged kubeconfig
    log_info "Creating final merged kubeconfig..."
    local final_kubeconfig="$HOME/.k3d/kubeconfig-all.yaml"
    local kubeconfig_list=""
    
    # Build list of kubeconfig files
    for cluster in "${CLUSTERS[@]}"; do
        if [ -z "$kubeconfig_list" ]; then
            kubeconfig_list="$HOME/.k3d/kubeconfig-$cluster.yaml"
        else
            kubeconfig_list="$kubeconfig_list:$HOME/.k3d/kubeconfig-$cluster.yaml"
        fi
    done
    
    # Merge all kubeconfig files
    KUBECONFIG="$kubeconfig_list" kubectl config view --flatten > "$final_kubeconfig"
    export KUBECONFIG="$final_kubeconfig"
    
    # Show available contexts
    log_info "Available Kubernetes contexts:"
    kubectl config get-contexts
    
    log_info "All clusters have been created successfully!"
    log_info "Use 'kubectl config use-context <cluster-name>' to switch between clusters"
    log_info "Your merged kubeconfig is at: $KUBECONFIG"
    
    # Set the first cluster as the current context
    if [ "${#CLUSTERS[@]}" -gt 0 ]; then
        kubectl config use-context "${CLUSTERS[0]}"
    fi
}

# Run main function
main 