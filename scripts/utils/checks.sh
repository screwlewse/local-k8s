#!/bin/bash

# Source the logger
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logger.sh"

# Check if a command exists
check_command() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Required command not found: $cmd"
        return 1
    fi
    log_debug "Command found: $cmd"
    return 0
}

# Check minimum Docker resources
check_docker_resources() {
    local min_cpu="$1"
    local min_memory="$2"  # in GB
    
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running"
        return 1
    fi
    
    # Get Docker resources - macOS ARM compatible
    local docker_info
    local cpu_count
    local memory_bytes
    local memory_gb
    
    docker_info="$(docker info --format '{{.NCPU}},{{.MemTotal}}' 2>/dev/null)"
    cpu_count="$(echo "$docker_info" | cut -d',' -f1)"
    memory_bytes="$(echo "$docker_info" | cut -d',' -f2)"
    # Use bc for floating point arithmetic
    memory_gb="$(echo "scale=2; $memory_bytes / 1024 / 1024 / 1024" | bc)"
    
    if [ "$cpu_count" -lt "$min_cpu" ]; then
        log_warn "Docker CPU count ($cpu_count) is less than recommended ($min_cpu)"
        # Don't fail on CPU check, just warn
    fi
    
    # Use bc for floating point comparison
    if [ "$(echo "$memory_gb < $min_memory" | bc -l)" -eq 1 ]; then
        log_warn "Docker memory ($memory_gb GB) is less than recommended ($min_memory GB)"
        # Don't fail on memory check, just warn
    fi
    
    log_info "Docker resources: $cpu_count CPUs, $memory_gb GB memory"
    return 0
}

# Check if ports are available
check_port() {
    local port="$1"
    if lsof -i :"$port" >/dev/null 2>&1; then
        log_error "Port $port is already in use"
        return 1
    fi
    log_debug "Port $port is available"
    return 0
}

# Check all required ports
check_required_ports() {
    local ports
    ports=(8080 8081 8443 9080 9081 9443 10080 10081 10443)
    local failed=0
    local port
    
    for port in "${ports[@]}"; do
        if ! check_port "$port"; then
            failed=1
        fi
    done
    
    if [ "$failed" -eq 1 ]; then
        log_error "Some required ports are not available"
        return 1
    fi
    
    log_info "All required ports are available"
    return 0
}

# Check disk space (macOS ARM compatible version)
check_disk_space() {
    local min_space_gb="$1"
    local docker_root
    
    # On macOS, Docker Desktop uses a different storage location
    if [ "$(uname)" = "Darwin" ]; then
        # Use $HOME/Library/Containers/com.docker.docker/Data/vms/0/data for macOS
        docker_root="$HOME/Library/Containers/com.docker.docker/Data"
    else
        docker_root="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null)"
    fi
    
    if [ ! -d "$docker_root" ]; then
        log_warn "Could not determine Docker root directory, skipping disk space check"
        return 0
    fi
    
    # Use macOS compatible df command and bc for floating point
    local available_blocks available_space
    available_blocks="$(df -k "$docker_root" | awk 'NR==2 {print $4}')"
    
    # Check if available_blocks is a number
    if ! [[ "$available_blocks" =~ ^[0-9]+$ ]]; then
        log_warn "Could not determine available disk space, skipping check"
        return 0
    fi
    
    # Convert KB to GB with bc
    available_space="$(echo "scale=2; $available_blocks / 1024 / 1024" | bc)"
    
    # Compare floating point numbers using bc
    if [ "$(echo "$available_space < $min_space_gb" | bc -l)" -eq 1 ]; then
        log_warn "Available disk space ($available_space GB) is less than recommended ($min_space_gb GB)"
        # Don't fail on disk space, just warn
    fi
    
    log_info "Disk space OK: $available_space GB available"
    return 0
}

# Run all checks
run_all_checks() {
    local failed=0
    local cmd
    
    log_info "Running system checks..."
    
    # Check required commands
    for cmd in docker kubectl k3d bc; do
        if ! check_command "$cmd"; then
            failed=1
        fi
    done
    
    # Check Docker resources (minimum 2 CPU, 4GB RAM for local development)
    # These are minimum requirements, will warn but not fail if not met
    check_docker_resources 2 4
    
    # Check ports (this is critical, must fail if ports are not available)
    if ! check_required_ports; then
        failed=1
    fi
    
    # Check disk space (minimum 10GB free, will warn but not fail)
    check_disk_space 10
    
    if [ "$failed" -eq 1 ]; then
        log_error "System checks failed"
        return 1
    fi
    
    log_info "All system checks passed"
    return 0
} 