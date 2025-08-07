# Script-Based Sequential Deployment Framework for LLMs

## Overview

This document provides a comprehensive framework for LLMs to create robust, production-ready sequential deployment systems. Based on the EventBridge Orchestrator implementation, this framework emphasizes error handling, state management, monitoring, and user experience.

---

## 🎯 Core Design Principles

### 1. **Sequential Step Architecture**
- Each deployment step is a **self-contained, executable script**
- Steps follow a **logical numeric sequence** (000, 010, 020, etc.)
- Each step has **clear prerequisites and outputs**
- Steps can be run **individually or as part of automated flow**

### 2. **Enterprise-Grade Robustness**
- **Comprehensive error handling** with automatic retries
- **State persistence** and checkpoint recovery
- **Graceful degradation** for non-critical failures
- **Prerequisites validation** before execution

### 3. **Developer Experience Focus**
- **Clear naming conventions** and intuitive progression
- **Real-time progress monitoring** and status feedback
- **Comprehensive logging** with categorized messages
- **Smart navigation** showing next steps automatically

---

## 📁 Required File Structure

When building a sequential deployment system, create this standardized structure:

```
project-name/
├── step-001-preflight-check.sh          # Prerequisites validation
├── step-000-interactive-setup.sh        # Initial configuration
├── step-010-first-deployment-step.sh    # First major deployment step
├── step-020-second-deployment-step.sh   # Second major deployment step
├── step-0XX-additional-steps.sh         # Additional steps as needed
├── step-050-validation-testing.sh       # End-to-end validation
├── step-998-pre-destroy-cleanup.sh      # Dependency cleanup
├── step-999-destroy-everything.sh       # Complete teardown
├── deploy-all.sh                        # Automated deployment
├── deployment-status.sh                 # Status monitoring
├── error-handling.sh                    # Common error handling library
├── step-navigation.sh                   # Navigation helper functions
├── .deployment-state/                   # State and logs (created at runtime)
│   ├── checkpoints.log
│   ├── errors.log
│   ├── warnings.log
│   ├── deployment.log
│   ├── step-*.status
│   └── step-*.log
└── README.md                           # Comprehensive documentation
```

---

## 🛠 Component Implementation Guide

### 1. **Error Handling Library (`error-handling.sh`)**

**Purpose:** Centralized error handling, logging, and retry logic

**Key Functions to Implement:**
```bash
# Essential error handling functions
log_error()                    # Log errors with timestamps
log_warning()                  # Log warnings with context
log_info()                     # Log informational messages
check_command_exists()         # Validate required tools
check_aws_credentials()        # Validate cloud credentials
retry_command()                # Retry with exponential backoff
create_checkpoint()            # Save deployment state
is_step_completed()           # Check if step was completed
show_deployment_summary()      # Display overall status
clean_deployment_state()       # Reset for fresh start
setup_error_handling()         # Initialize error handling
```

**Implementation Pattern:**
- Use **colored output** for different message types
- Implement **exponential backoff** for retries
- Create **timestamped log files** in `.deployment-state/`
- Provide **context-aware error messages** with solutions
- Support **graceful degradation** for non-critical failures

### 2. **Navigation System (`step-navigation.sh`)**

**Purpose:** Smart step progression and user guidance

**Key Functions to Implement:**
```bash
detect_next_step()            # Auto-detect next script in sequence
show_next_step()              # Display next step with description
validate_prerequisites()      # Check if previous steps completed
```

**Implementation Pattern:**
- **Auto-detect** next step based on current script name
- **Validate dependencies** before allowing step execution
- **Display helpful descriptions** of what each step does
- **Handle special cases** (e.g., after testing, go to destroy)

### 3. **Preflight Check Script (`step-001-preflight-check.sh`)**

**Purpose:** Validate system prerequisites before deployment

**What to Check:**
```bash
# Required tools and versions
check_command "aws" "https://aws.amazon.com/cli/"
check_command "terraform" "https://terraform.io/downloads"
check_command "jq" "https://stedolan.github.io/jq/"
check_command "git" "https://git-scm.com/"

# Cloud credentials and configuration
check_aws_credentials
check_aws_region
check_iam_permissions_hint

# System resources
check_disk_space
check_nodejs_version          # If applicable
check_terraform_version

# Version compatibility checks
validate_tool_versions
```

**Implementation Pattern:**
- **Fail fast** if critical prerequisites missing
- **Provide installation hints** for missing tools
- **Check version compatibility** for known issues
- **Create state tracking** when prerequisites met
- **Guide user to next step** upon success

### 4. **Configuration Script (`step-000-interactive-setup.sh`)**

**Purpose:** Interactive configuration and environment setup

**What to Configure:**
```bash
# Environment variables
AWS_REGION=us-east-2
ENVIRONMENT=dev
PROJECT_NAME=your-project
DEPLOYMENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Service-specific configuration
SERVICE_SPECIFIC_VAR=value

# Generate configuration files
create_env_file              # .env file
create_terraform_vars        # terraform/terraform.tfvars
create_deployment_config     # deployment-config.env
```

**Implementation Pattern:**
- **Interactive prompts** with sensible defaults
- **Validation** of user input
- **Configuration file generation** for subsequent steps
- **Environment detection** and auto-configuration where possible

### 5. **Core Deployment Steps (`step-0XX-*.sh`)**

**Purpose:** Individual deployment operations with error handling

**Standard Structure for Each Step:**
```bash
#!/bin/bash

# 1. Source dependencies
source "$(dirname "$0")/step-navigation.sh" || { echo "Navigation functions not found"; }
source "$(dirname "$0")/error-handling.sh" || { echo "Error handling not found"; set -e; }

# 2. Initialize error handling
SCRIPT_NAME="step-0XX-descriptive-name"
setup_error_handling "$SCRIPT_NAME"
create_checkpoint "$SCRIPT_NAME" "in_progress" "$SCRIPT_NAME"

# 3. Validate prerequisites
if ! check_deployment_prerequisites "$SCRIPT_NAME"; then
    log_error "Prerequisites not met" "$SCRIPT_NAME"
    exit 1
fi

# 4. Load configuration
if [ -f ".env" ]; then
    source .env
    log_info "Configuration loaded" "$SCRIPT_NAME"
else
    log_error "Configuration not found. Run step-000 first." "$SCRIPT_NAME"
    exit 1
fi

# 5. Main deployment logic with error handling
log_info "Starting deployment operation..." "$SCRIPT_NAME"

if retry_command 3 10 "$SCRIPT_NAME" your_deployment_command; then
    log_info "Deployment operation successful" "$SCRIPT_NAME"
else
    log_error "Deployment operation failed" "$SCRIPT_NAME"
    exit 1
fi

# 6. Validation and checkpoint
create_checkpoint "$SCRIPT_NAME" "completed" "$SCRIPT_NAME"
log_info "Step completed successfully" "$SCRIPT_NAME"

# 7. Show next step
if declare -f show_next_step > /dev/null; then
    show_next_step "$(basename "$0")" "$(dirname "$0")"
fi
```

### 6. **Validation Script (`step-050-validation-testing.sh`)**

**Purpose:** Comprehensive end-to-end system validation

**What to Test:**
```bash
# Infrastructure validation
validate_cloud_resources
check_service_health
verify_configurations

# Functional testing
test_primary_workflows
test_error_scenarios
validate_monitoring_setup

# Operational health check
check_resource_utilization
validate_security_configuration
test_disaster_recovery_readiness
```

**Implementation Pattern:**
- **Comprehensive test suite** covering all deployed components
- **Health check dashboard** showing system status
- **Performance validation** and resource checks
- **Security validation** and compliance checks
- **Generate test reports** with detailed results

### 7. **Automated Deployment Script (`deploy-all.sh`)**

**Purpose:** Fully automated deployment with user control

**Key Features:**
```bash
# Command line options
--auto-approve              # Non-interactive mode
--fresh-start              # Clean state and restart
--skip-preflight          # Skip prerequisite checks
--help                    # Show usage information

# Interactive prompts
prompt_continue()          # Ask user before each major step
can_continue_after_failure() # Handle partial failures

# Step execution
run_step()                # Execute individual step with logging
```

**Implementation Pattern:**
- **Interactive by default** with override options
- **Graceful failure handling** with recovery options
- **Comprehensive logging** of all operations
- **State persistence** for resume capability
- **Final summary** with next steps

### 8. **Status Monitoring Script (`deployment-status.sh`)**

**Purpose:** Real-time deployment progress and health monitoring

**Status Categories:**
```bash
# Step status tracking
display_status "step-name" "Display Name"
# Possible states: completed, in_progress, failed, not_started

# Resource health checking
check_cloud_resources
validate_service_endpoints
monitor_system_health

# Error and warning summaries
show_error_count
show_recent_errors
show_warning_summary
```

**Implementation Pattern:**
- **Visual status indicators** (✅ ❌ 🔄 ⭕)
- **Real-time cloud resource checking**
- **Error and warning summaries**
- **Next action recommendations**
- **Log file locations and contents**

### 9. **Cleanup Scripts (`step-998-*.sh`, `step-999-*.sh`)**

**Purpose:** Proper resource cleanup handling dependencies

**Two-Phase Destroy Pattern:**
```bash
# step-998-pre-destroy-cleanup.sh
# Handle API-level dependencies that prevent Terraform destroy
remove_service_dependencies
cleanup_external_resources
prepare_for_infrastructure_destroy

# step-999-destroy-everything.sh  
# Complete infrastructure teardown
terraform_destroy_with_retry
cleanup_local_state
verify_complete_cleanup
```

---

## 🎨 User Experience Guidelines

### 1. **Consistent Visual Design**

**Color Coding:**
```bash
RED='\033[0;31m'      # Errors and failures
GREEN='\033[0;32m'    # Success and completion
BLUE='\033[0;34m'     # Information and progress
YELLOW='\033[1;33m'   # Warnings and important notes
CYAN='\033[0;36m'     # Highlights and emphasis
BOLD='\033[1m'        # Headers and important text
NC='\033[0m'          # No color (reset)
```

**Icon Usage:**
- ✅ Success/Completed
- ❌ Error/Failed  
- ⚠️ Warning/Attention needed
- 🔄 In progress/Working
- ⭕ Not started/Pending
- 🎯 Target/Goal
- 🔧 Tools/Configuration
- 📊 Status/Monitoring
- 🚀 Deployment/Launch

### 2. **Clear Progress Communication**

**Step Headers:**
```bash
echo "🔧 Step 1: Setting up Prerequisites"
echo "=================================="
```

**Progress Indicators:**
```bash
echo -e "${BLUE}📋 Checking system requirements...${NC}"
echo -e "${GREEN}✅ All prerequisites met!${NC}"
echo -e "${YELLOW}⚠️ Warning: Non-critical issue detected${NC}"
```

**Next Step Guidance:**
```bash
echo -e "\n${CYAN}Next: Run step-020-deploy-infrastructure.sh${NC}"
echo -e "${BLUE}This will deploy the core infrastructure components${NC}"
```

### 3. **Error Messages with Context**

**Error Pattern:**
```bash
log_error "Specific error description" "$SCRIPT_NAME"
echo -e "${YELLOW}💡 Suggestion: Try running 'command-to-fix'${NC}"
echo -e "${BLUE}💡 Documentation: See troubleshooting section${NC}"
```

**Recovery Guidance:**
```bash
echo -e "${CYAN}Recovery options:${NC}"
echo -e "${BLUE}• Retry: Re-run this script${NC}"
echo -e "${BLUE}• Skip: Continue to next step (if non-critical)${NC}"
echo -e "${BLUE}• Reset: Run with --fresh-start flag${NC}"
```

---

## 📊 State Management Patterns

### 1. **Checkpoint System**

**State Directory Structure:**
```
.deployment-state/
├── checkpoints.log              # Timestamp, step, status
├── errors.log                   # Error history with context
├── warnings.log                 # Warning history
├── deployment.log               # All operations log
├── step-{name}.status           # Individual step status
└── step-{name}.log             # Individual step logs
```

**Checkpoint Implementation:**
```bash
create_checkpoint() {
    local step_name="$1"
    local status="$2"  # pending, in_progress, completed, failed
    local script_name="$3"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    echo "${timestamp} ${step_name} ${status}" >> "${DEPLOYMENT_STATE_DIR}/checkpoints.log"
    echo "${status}" > "${DEPLOYMENT_STATE_DIR}/${step_name}.status"
    log_info "Checkpoint: ${step_name} -> ${status}" "$script_name"
}
```

### 2. **Resume Capability**

**Step Completion Check:**
```bash
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
```

**Automated Resume Logic:**
```bash
# In deploy-all.sh
if is_step_completed "$step_base"; then
    log_info "$step_name already completed, skipping" "$SCRIPT_NAME"
    return 0
fi
```

---

## 🔄 Retry and Recovery Patterns

### 1. **Exponential Backoff Retry**

```bash
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
```

### 2. **Graceful Degradation**

```bash
handle_non_critical_error() {
    local error_description="$1"
    local script_name="$2"
    local continue_anyway="$3"
    
    log_warning "$error_description (non-critical)" "$script_name"
    
    if [ "$continue_anyway" = true ]; then
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
```

### 3. **Service-Specific Error Handling**

```bash
handle_terraform_error() {
    local exit_code="$1"
    local log_file="$2"
    local script_name="$3"
    
    if [ "$exit_code" -ne 0 ]; then
        # Check for specific known issues
        if grep -q "already exists" "$log_file" 2>/dev/null; then
            log_warning "Resources already exist (idempotent operation)" "$script_name"
            return 0  # Treat as success
        fi
        
        if grep -q "timeout" "$log_file" 2>/dev/null; then
            log_error "Operation timed out. Service might be experiencing delays." "$script_name"
            return 2  # Special code for retry
        fi
        
        log_error "Operation failed. Check $log_file for details." "$script_name"
        return 1
    fi
    
    return 0
}
```

---

## 📚 Documentation Standards

### 1. **README.md Structure**

**Required Sections:**
- **Quick Start** with automated and manual options
- **Deployment Options** table with use cases
- **Enhanced Features** highlighting robustness
- **Troubleshooting Guide** with common issues
- **Component Overview** explaining what's deployed
- **Developer Integration** examples

### 2. **Inline Documentation**

**Script Headers:**
```bash
#!/bin/bash

# [Project Name] - [Step Description]
# This script [what it does] and [why it's important]
# Prerequisites: [what must be done first]
# Outputs: [what it creates/configures]
```

**Function Documentation:**
```bash
# Function to [purpose]
# Usage: function_name "param1" "param2"
# Returns: 0 on success, 1 on error
function_name() {
    local param1="$1"
    local param2="$2"
    # Implementation
}
```

### 3. **Help Text Standards**

**Command Usage:**
```bash
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Description of what this script does"
    echo ""
    echo "Options:"
    echo "  --option1        Description of option 1"
    echo "  --option2        Description of option 2"
    echo "  --help, -h       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                # Default behavior"
    echo "  $0 --option1      # Alternative behavior"
    exit 0
fi
```

---

## ⚡ Advanced Implementation Patterns

### 1. **Cloud Provider Abstraction**

When building for multiple cloud providers:

```bash
# Abstract cloud operations
deploy_infrastructure() {
    case "$CLOUD_PROVIDER" in
        "aws")
            deploy_aws_infrastructure
            ;;
        "azure")
            deploy_azure_infrastructure
            ;;
        "gcp")
            deploy_gcp_infrastructure
            ;;
        *)
            log_error "Unsupported cloud provider: $CLOUD_PROVIDER"
            exit 1
            ;;
    esac
}
```

### 2. **Environment Management**

```bash
# Environment-specific configuration
load_environment_config() {
    local env="$1"
    local config_file="environments/${env}.env"
    
    if [ -f "$config_file" ]; then
        source "$config_file"
        log_info "Loaded configuration for environment: $env"
    else
        log_error "Configuration not found for environment: $env"
        exit 1
    fi
}
```

### 3. **Parallel Execution Support**

```bash
# Run independent steps in parallel
run_parallel_steps() {
    local steps=("$@")
    local pids=()
    
    for step in "${steps[@]}"; do
        run_step "$step" &
        pids+=($!)
    done
    
    # Wait for all to complete
    for pid in "${pids[@]}"; do
        wait $pid || log_error "Parallel step failed"
    done
}
```

---

## 🧪 Testing and Validation Framework

### 1. **Unit Tests for Scripts**

```bash
# test-step-functions.sh
test_retry_command() {
    # Test retry logic with mock failures
    # Verify exponential backoff
    # Check max attempts limit
}

test_checkpoint_creation() {
    # Test state file creation
    # Verify timestamp format
    # Check status persistence
}
```

### 2. **Integration Tests**

```bash
# test-deployment-flow.sh  
test_full_deployment() {
    # Run complete deployment in test environment
    # Verify all components deployed
    # Test cleanup process
}

test_failure_recovery() {
    # Simulate failures at different points
    # Test resume capability
    # Verify state consistency
}
```

### 3. **Validation Hooks**

```bash
# Pre/post step validation
validate_pre_step() {
    local step_name="$1"
    # Check prerequisites
    # Validate configuration
    # Ensure clean state
}

validate_post_step() {
    local step_name="$1"
    # Verify expected outputs
    # Check resource creation
    # Validate configurations
}
```

---

## 🎯 Best Practices Summary

### 1. **Script Design**
- ✅ **Self-contained**: Each script should be runnable independently
- ✅ **Idempotent**: Safe to run multiple times
- ✅ **Atomic**: Either complete successfully or fail cleanly
- ✅ **Logged**: Comprehensive logging of all operations
- ✅ **Recoverable**: Support resume from failure points

### 2. **Error Handling**
- ✅ **Fail fast**: Stop immediately on critical errors
- ✅ **Retry transient**: Automatic retry for network/API failures
- ✅ **Degrade gracefully**: Continue when possible with warnings
- ✅ **Provide context**: Clear error messages with solutions
- ✅ **Track state**: Persistent error and warning logs

### 3. **User Experience**
- ✅ **Clear progress**: Visual indicators and status updates
- ✅ **Predictable flow**: Logical step sequence
- ✅ **Helpful guidance**: Next steps and troubleshooting hints
- ✅ **Recovery options**: Multiple ways to handle failures
- ✅ **Comprehensive docs**: README with all necessary information

### 4. **Production Readiness**
- ✅ **Automation support**: Non-interactive modes for CI/CD
- ✅ **State management**: Persistent tracking and recovery
- ✅ **Monitoring**: Real-time status and health checking
- ✅ **Cleanup**: Proper resource teardown procedures
- ✅ **Security**: Validate credentials and permissions

---

## 🐛 Critical Lessons Learned

### **Directory Management and Path Handling**

**⚠️ CRITICAL ISSUE:** Scripts that change directories break relative path logging

**Problem discovered:** When deployment scripts execute `cd terraform` or change to other directories, relative paths like `.deployment-state/deployment.log` no longer resolve correctly, causing:
- "No such file or directory" errors in log output
- Failed logging operations that break error handling
- False positive error reports

**✅ Solution implemented:**
```bash
# ❌ WRONG - Relative path breaks when directory changes
DEPLOYMENT_STATE_DIR=".deployment-state"

# ✅ CORRECT - Absolute path works from any directory
DEPLOYMENT_STATE_DIR="$(pwd)/.deployment-state"
```

**📋 Implementation pattern for error-handling.sh:**
```bash
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
```

### **Error Trap Management**

**⚠️ CRITICAL ISSUE:** ERR traps fire on successful script completion

**Problem discovered:** Bash ERR traps trigger even when scripts complete successfully, causing false positive error reports

**✅ Solution implemented:**
```bash
# ❌ WRONG - ERR trap causes false positives
setup_error_handling() {
    set -eE
    set -o pipefail
    trap "cleanup_on_error '$script_name'" ERR  # Fires even on success
}

# ✅ CORRECT - Minimal error handling without problematic traps
setup_error_handling() {
    local script_name="$1"
    
    # Enable basic error handling without problematic traps
    set -e
    set -o pipefail
    
    # Don't set error traps - they cause false positives
    # Scripts should handle their own error checking
    
    log_info "Error handling initialized for $script_name" "$script_name"
}
```

### **Robust Logging Patterns**

**✅ Key patterns for bulletproof logging:**

```bash
# Always use 2>/dev/null || true for non-critical log operations
echo "${timestamp} INFO [${script_name}]: ${message}" >> "${DEPLOYMENT_STATE_DIR}/deployment.log" 2>/dev/null || true

# Initialize all log files immediately when sourced
touch "${DEPLOYMENT_STATE_DIR}/deployment.log" 2>/dev/null || true
touch "${DEPLOYMENT_STATE_DIR}/errors.log" 2>/dev/null || true

# Check for log file existence before writing (alternative approach)
if [ -w "${DEPLOYMENT_STATE_DIR}/deployment.log" ]; then
    echo "${timestamp} INFO: ${message}" >> "${DEPLOYMENT_STATE_DIR}/deployment.log"
fi
```

### **Directory Change Safety**

**📋 Safe patterns for scripts that change directories:**

```bash
# Method 1: Store original directory and return
ORIGINAL_DIR="$(pwd)"
cd terraform
# Do terraform operations
cd "$ORIGINAL_DIR"

# Method 2: Use absolute paths for all log operations
DEPLOYMENT_STATE_DIR="$(pwd)/.deployment-state"  # Set before any cd commands

# Method 3: Use subshells to contain directory changes
(
    cd terraform
    terraform apply
)
# Still in original directory
```

### **State Management Robustness**

**✅ Enhanced state tracking patterns:**

```bash
# Robust checkpoint creation
create_checkpoint() {
    local step_name="$1"
    local status="$2"
    local script_name="$3"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Use absolute path and handle failures gracefully
    local state_dir="$(pwd)/.deployment-state"
    mkdir -p "$state_dir" 2>/dev/null || return 0
    
    echo "${timestamp} ${step_name} ${status}" >> "${state_dir}/checkpoints.log" 2>/dev/null || true
    echo "${status}" > "${state_dir}/${step_name}.status" 2>/dev/null || true
    
    log_info "Checkpoint: ${step_name} -> ${status}" "$script_name"
}
```

---

## 🚀 Implementation Checklist

When building a new sequential deployment system, ensure you implement:

### Core Infrastructure
- [ ] Error handling library (`error-handling.sh`)
- [ ] Navigation system (`step-navigation.sh`)
- [ ] State management directory (`.deployment-state/`)
- [ ] Automated deployment script (`deploy-all.sh`)
- [ ] Status monitoring script (`deployment-status.sh`)

### Sequential Steps
- [ ] Preflight check (`step-001-*`)
- [ ] Interactive setup (`step-000-*`) 
- [ ] Core deployment steps (`step-0XX-*`)
- [ ] Validation testing (`step-050-*`)
- [ ] Cleanup scripts (`step-998-*`, `step-999-*`)

### User Experience
- [ ] Consistent visual design and colors
- [ ] Clear progress indicators
- [ ] Helpful error messages with solutions
- [ ] Comprehensive README documentation
- [ ] Command-line help text

### Robustness Features
- [ ] Retry logic with exponential backoff
- [ ] Checkpoint-based recovery
- [ ] Prerequisites validation
- [ ] Graceful error degradation
- [ ] Comprehensive logging
- [ ] **CRITICAL**: Absolute paths for state directories (not relative paths)
- [ ] **CRITICAL**: Error trap management (avoid false positives)
- [ ] **CRITICAL**: Directory change safety patterns

### Production Features
- [ ] Non-interactive automation support
- [ ] Fresh start and cleanup capabilities
- [ ] Real-time monitoring and status
- [ ] CI/CD integration examples
- [ ] Security and compliance validation

---

This framework provides a complete blueprint for creating robust, production-ready sequential deployment systems that prioritize reliability, user experience, and maintainability. Follow these patterns to build deployment tools that work reliably in enterprise environments while remaining accessible for development use cases.
