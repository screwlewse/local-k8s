#!/bin/bash

# Source utility scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../scripts/utils/logger.sh"

# Set up error handling
set -euo pipefail

# Configuration
HOSTS_FILE="/etc/hosts"
HOSTS_MARKER="# START K3D LOCAL DOMAINS"
HOSTS_END_MARKER="# END K3D LOCAL DOMAINS"

# Get the LoadBalancer IP
get_ingress_ip() {
    local cluster="$1"
    kubectl --context "k3d-${cluster}" -n ingress-nginx get svc ingress-nginx-controller \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo ""
}

# Function to generate hosts entries for dev environment
generate_dev_entries() {
    local ip="$1"
    echo "$ip argocd.dev.local"
    echo "$ip prometheus.dev.local"
    echo "$ip grafana.dev.local"
    echo "$ip app.dev.local"
    echo "$ip api.dev.local"
    echo "$ip docs.dev.local"
}

# Function to generate hosts entries for staging environment
generate_staging_entries() {
    local ip="$1"
    echo "$ip argocd.staging.local"
    echo "$ip prometheus.staging.local"
    echo "$ip grafana.staging.local"
    echo "$ip app.staging.local"
    echo "$ip api.staging.local"
}

# Function to generate hosts entries for prod environment
generate_prod_entries() {
    local ip="$1"
    echo "$ip app.prod.local"
    echo "$ip api.prod.local"
}

# Main function to update hosts file
update_hosts() {
    local tmp_hosts=$(mktemp)
    local found_marker=0
    
    # Read existing hosts file, excluding our section
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "$HOSTS_MARKER" ]]; then
            found_marker=1
            continue
        fi
        if [[ "$found_marker" -eq 1 ]]; then
            if [[ "$line" == "$HOSTS_END_MARKER" ]]; then
                found_marker=0
                continue
            fi
            continue
        fi
        echo "$line" >> "$tmp_hosts"
    done < "$HOSTS_FILE"
    
    # Add our marker
    echo -e "\n$HOSTS_MARKER" >> "$tmp_hosts"
    
    # Add entries for dev environment
    ip=$(get_ingress_ip "dev")
    if [[ -n "$ip" ]]; then
        log_info "Adding entries for dev environment (IP: $ip)"
        generate_dev_entries "$ip" >> "$tmp_hosts"
    else
        log_warn "Could not get IP for dev environment, skipping..."
    fi
    
    # Add entries for staging environment
    ip=$(get_ingress_ip "staging")
    if [[ -n "$ip" ]]; then
        log_info "Adding entries for staging environment (IP: $ip)"
        generate_staging_entries "$ip" >> "$tmp_hosts"
    else
        log_warn "Could not get IP for staging environment, skipping..."
    fi
    
    # Add entries for prod environment
    ip=$(get_ingress_ip "prod")
    if [[ -n "$ip" ]]; then
        log_info "Adding entries for prod environment (IP: $ip)"
        generate_prod_entries "$ip" >> "$tmp_hosts"
    else
        log_warn "Could not get IP for prod environment, skipping..."
    fi
    
    # Add end marker
    echo "$HOSTS_END_MARKER" >> "$tmp_hosts"
    
    # Check if we have sudo access
    if [[ $EUID -ne 0 ]]; then
        log_info "Requesting sudo access to update $HOSTS_FILE"
        sudo cp "$tmp_hosts" "$HOSTS_FILE"
    else
        cp "$tmp_hosts" "$HOSTS_FILE"
    fi
    
    rm "$tmp_hosts"
    
    log_info "Updated $HOSTS_FILE successfully"
}

# Main execution
main() {
    log_info "Starting hosts file update..."
    
    # Verify kubectl access
    if ! kubectl version --client &>/dev/null; then
        log_error "kubectl not found. Please install kubectl first."
        exit 1
    fi
    
    # Update hosts file
    if ! update_hosts; then
        log_error "Failed to update hosts file"
        exit 1
    fi
    
    log_info "Local DNS configuration completed successfully!"
    log_info "You can now access services using domains like:"
    log_info "- https://argocd.dev.local"
    log_info "- https://app.staging.local"
    log_info "- https://api.prod.local"
}

# Run main function
main 