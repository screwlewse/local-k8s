#!/bin/bash

# Log levels (0=DEBUG, 1=INFO, 2=WARN, 3=ERROR, 4=FATAL)
LOG_LEVEL=${LOG_LEVEL:-"INFO"}
LOG_DIR=${LOG_DIR:-"logs"}
LOG_FILE="${LOG_DIR}/k8s-local-$(date +%Y%m%d).log"

# ANSI color codes
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

# Initialize logging
init_logging() {
    mkdir -p "${LOG_DIR}"
    touch "${LOG_FILE}"
    # Rotate logs (keep last 7 days)
    find "${LOG_DIR}" -name "k8s-local-*.log" -mtime +7 -delete 2>/dev/null || true
}

# Get numeric log level
get_log_level() {
    local level="$1"
    case "$level" in
        "DEBUG") echo "0" ;;
        "INFO")  echo "1" ;;
        "WARN")  echo "2" ;;
        "ERROR") echo "3" ;;
        "FATAL") echo "4" ;;
        *)       echo "1" ;;
    esac
}

# Internal logging function
_log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local numeric_level
    numeric_level="$(get_log_level "$level")"
    local current_level
    current_level="$(get_log_level "$LOG_LEVEL")"
    
    # Check if we should log this message based on LOG_LEVEL
    if [ "$numeric_level" -ge "$current_level" ]; then
        # Format the message
        local formatted_message="${timestamp} [${level}] ${message}"
        
        # Add color to console output
        case $level in
            "DEBUG") local colored_message="${BLUE}${formatted_message}${NC}" ;;
            "INFO")  local colored_message="${GREEN}${formatted_message}${NC}" ;;
            "WARN")  local colored_message="${YELLOW}${formatted_message}${NC}" ;;
            "ERROR") local colored_message="${RED}${formatted_message}${NC}" ;;
            "FATAL") local colored_message="${RED}${BOLD}${formatted_message}${NC}" ;;
            *)       local colored_message="${formatted_message}" ;;
        esac
        
        # Output to console and log file
        echo -e "${colored_message}"
        echo "${formatted_message}" >> "${LOG_FILE}"
    fi
}

# Public logging functions
log_debug() { _log "DEBUG" "$*"; }
log_info()  { _log "INFO"  "$*"; }
log_warn()  { _log "WARN"  "$*"; }
log_error() { _log "ERROR" "$*"; }
log_fatal() { _log "FATAL" "$*"; exit 1; }

# Function to log command outputs
log_cmd() {
    local cmd="$1"
    local output
    local exit_code
    
    log_debug "Executing command: $cmd"
    # Use eval to handle command properly
    output="$(eval "$cmd" 2>&1)" || {
        exit_code="$?"
        log_error "Command failed with exit code $exit_code: $cmd"
        log_error "Output: $output"
        return "$exit_code"
    }
    
    log_debug "Command succeeded: $cmd"
    log_debug "Output: $output"
    echo "$output"
    return 0
}

# Initialize logging when this script is sourced
init_logging 