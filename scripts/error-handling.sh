#!/bin/bash

# Error Handling Library for Smart Transcription Router
# Based on Script-Based Sequential Deployment Framework
# Provides centralized error handling, logging, and retry logic

# Color definitions for consistent output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Global variables for error tracking
ERROR_COUNT=0
WARNING_COUNT=0
# Use absolute path to handle directory changes (like cd terraform)
DEPLOYMENT_STATE_DIR="$(pwd)/.deployment-state"

# Ensure deployment state directory and log files exist immediately
if [ ! -d "$DEPLOYMENT_STATE_DIR" ]; then
    mkdir -p "$DEPLOYMENT_STATE_DIR" 2>/dev/null || {
        echo "Warning: Could not create deployment state directory"
        # Fallback to current directory for logs
        DEPLOYMENT_STATE_DIR="."
    }
fi

# Initialize log files if they don't exist
touch "${DEPLOYMENT_STATE_DIR}/deployment.log" 2>/dev/null || true
touch "${DEPLOYMENT_STATE_DIR}/errors.log" 2>/dev/null || true
touch "${DEPLOYMENT_STATE_DIR}/warnings.log" 2>/dev/null || true
touch "${DEPLOYMENT_STATE_DIR}/checkpoints.log" 2>/dev/null || true

# Function to log error messages with timestamps
log_error() {
    local message="$1"
    local script_name="${2:-unknown}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    ERROR_COUNT=$((ERROR_COUNT + 1))
    
    # Display to console with color
    echo -e "${RED}❌ ERROR [${script_name}]: ${message}${NC}" >&2
    
    # Log to files with error handling
    echo "${timestamp} ERROR [${script_name}]: ${message}" >> "${DEPLOYMENT_STATE_DIR}/errors.log" 2>/dev/null || true
    echo "${timestamp} ERROR [${script_name}]: ${message}" >> "${DEPLOYMENT_STATE_DIR}/deployment.log" 2>/dev/null || true
}

# Function to log warning messages with timestamps
log_warning() {
    local message="$1"
    local script_name="${2:-unknown}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    WARNING_COUNT=$((WARNING_COUNT + 1))
    
    # Display to console with color
    echo -e "${YELLOW}⚠️ WARNING [${script_name}]: ${message}${NC}"
    
    # Log to files with error handling
    echo "${timestamp} WARNING [${script_name}]: ${message}" >> "${DEPLOYMENT_STATE_DIR}/warnings.log" 2>/dev/null || true
    echo "${timestamp} WARNING [${script_name}]: ${message}" >> "${DEPLOYMENT_STATE_DIR}/deployment.log" 2>/dev/null || true
}

# Function to log informational messages with timestamps
log_info() {
    local message="$1"
    local script_name="${2:-unknown}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Display to console with color
    echo -e "${BLUE}ℹ️ INFO [${script_name}]: ${message}${NC}"
    
    # Log to files with error handling
    echo "${timestamp} INFO [${script_name}]: ${message}" >> "${DEPLOYMENT_STATE_DIR}/deployment.log" 2>/dev/null || true
}

# Function to log success messages with timestamps
log_success() {
    local message="$1"
    local script_name="${2:-unknown}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Display to console with color
    echo -e "${GREEN}✅ SUCCESS [${script_name}]: ${message}${NC}"
    
    # Log to files with error handling
    echo "${timestamp} SUCCESS [${script_name}]: ${message}" >> "${DEPLOYMENT_STATE_DIR}/deployment.log" 2>/dev/null || true
}

# Function to check if a command exists
check_command_exists() {
    local command="$1"
    local install_url="${2:-}"
    local script_name="${3:-unknown}"
    
    if ! command -v "$command" &> /dev/null; then
        log_error "Required command '$command' not found in PATH" "$script_name"
        if [ -n "$install_url" ]; then
            echo -e "${YELLOW}💡 Installation instructions: ${install_url}${NC}"
        fi
        return 1
    fi
    
    log_info "Found required command: $command" "$script_name"
    return 0
}

# Function to check AWS credentials
check_aws_credentials() {
    local script_name="${1:-unknown}"
    
    log_info "Checking AWS credentials..." "$script_name"
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid" "$script_name"
        echo -e "${YELLOW}💡 Run: aws configure${NC}"
        return 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    local region=$(aws configure get region 2>/dev/null)
    
    log_success "AWS credentials valid (Account: $account_id, Region: $region)" "$script_name"
    return 0
}

# Function to retry a command with exponential backoff
retry_command() {
    local max_attempts="$1"
    local delay="$2"
    local script_name="$3"
    shift 3
    local cmd=("$@")
    
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        log_info "Attempt $attempt/$max_attempts: ${cmd[*]}" "$script_name"
        
        if "${cmd[@]}"; then
            log_success "Command succeeded on attempt $attempt" "$script_name"
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            log_warning "Command failed, retrying in ${delay}s..." "$script_name"
            sleep "$delay"
            delay=$((delay * 2))  # Exponential backoff
        fi
        
        ((attempt++))
    done
    
    log_error "Command failed after $max_attempts attempts: ${cmd[*]}" "$script_name"
    return 1
}

# Function to create a checkpoint
create_checkpoint() {
    local step_name="$1"
    local status="$2"  # pending, in_progress, completed, failed
    local script_name="$3"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Use absolute path and handle failures gracefully
    local state_dir="$(pwd)/.deployment-state"
    mkdir -p "$state_dir" 2>/dev/null || return 0
    
    echo "${timestamp} ${step_name} ${status}" >> "${state_dir}/checkpoints.log" 2>/dev/null || true
    echo "${status}" > "${state_dir}/${step_name}.status" 2>/dev/null || true
    
    log_info "Checkpoint: ${step_name} -> ${status}" "$script_name"
}

# Function to check if a step is completed
is_step_completed() {
    local step_name="$1"
    local status_file="${DEPLOYMENT_STATE_DIR}/${step_name}.status"
    
    if [ -f "$status_file" ]; then
        local status=$(cat "$status_file" 2>/dev/null)
        [ "$status" = "completed" ]
    else
        return 1
    fi
}

# Function to validate prerequisites
check_deployment_prerequisites() {
    local script_name="$1"
    local prerequisites="${2:-}"
    
    if [ -z "$prerequisites" ]; then
        return 0  # No prerequisites
    fi
    
    log_info "Checking prerequisites: $prerequisites" "$script_name"
    
    for prereq in $prerequisites; do
        if ! is_step_completed "$prereq"; then
            log_error "Prerequisite not met: $prereq not completed" "$script_name"
            return 1
        fi
    done
    
    log_success "All prerequisites met" "$script_name"
    return 0
}

# Function to setup error handling for a script
setup_error_handling() {
    local script_name="$1"
    
    # Enable basic error handling without problematic traps
    set -e
    set -o pipefail
    
    # Don't set error traps - they cause false positives
    # Scripts should handle their own error checking
    
    log_info "Error handling initialized for $script_name" "$script_name"
}

# Function to show deployment summary
show_deployment_summary() {
    local script_name="${1:-deployment}"
    
    echo -e "\n${CYAN}=== Deployment Summary ===${NC}"
    echo -e "${BLUE}Total Errors: ${ERROR_COUNT}${NC}"
    echo -e "${YELLOW}Total Warnings: ${WARNING_COUNT}${NC}"
    echo -e "${GREEN}Log Directory: ${DEPLOYMENT_STATE_DIR}${NC}"
    
    if [ $ERROR_COUNT -gt 0 ]; then
        echo -e "\n${RED}❌ Deployment completed with errors${NC}"
        echo -e "${YELLOW}Check ${DEPLOYMENT_STATE_DIR}/errors.log for details${NC}"
    else
        echo -e "\n${GREEN}✅ Deployment completed successfully${NC}"
    fi
}

# Function to clean deployment state for fresh start
clean_deployment_state() {
    local script_name="${1:-cleanup}"
    
    log_warning "Cleaning deployment state for fresh start" "$script_name"
    
    if [ -d "$DEPLOYMENT_STATE_DIR" ]; then
        rm -rf "$DEPLOYMENT_STATE_DIR"
        log_success "Deployment state cleaned" "$script_name"
    fi
    
    # Recreate directories and files
    mkdir -p "$DEPLOYMENT_STATE_DIR" 2>/dev/null || true
    touch "${DEPLOYMENT_STATE_DIR}/deployment.log" 2>/dev/null || true
    touch "${DEPLOYMENT_STATE_DIR}/errors.log" 2>/dev/null || true
    touch "${DEPLOYMENT_STATE_DIR}/warnings.log" 2>/dev/null || true
    touch "${DEPLOYMENT_STATE_DIR}/checkpoints.log" 2>/dev/null || true
    
    ERROR_COUNT=0
    WARNING_COUNT=0
}

# Function to handle non-critical errors
handle_non_critical_error() {
    local error_description="$1"
    local script_name="$2"
    local continue_anyway="${3:-false}"
    
    log_warning "$error_description (non-critical)" "$script_name"
    
    if [ "$continue_anyway" = "true" ]; then
        log_info "Continuing deployment despite non-critical error" "$script_name"
        return 0
    else
        echo -e "${YELLOW}Continue anyway? (y/N): ${NC}"
        read -r response
        case "$response" in
            [yY]|[yY][eE][sS])
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    fi
}

# Export all functions for use in other scripts
export -f log_error
export -f log_warning
export -f log_info
export -f log_success
export -f check_command_exists
export -f check_aws_credentials
export -f retry_command
export -f create_checkpoint
export -f is_step_completed
export -f check_deployment_prerequisites
export -f setup_error_handling
export -f show_deployment_summary
export -f clean_deployment_state
export -f handle_non_critical_error

log_info "Error handling library loaded successfully" "error-handling.sh"