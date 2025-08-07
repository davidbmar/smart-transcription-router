#!/bin/bash

# Step Navigation Library for Smart Transcription Router
# Provides smart step progression and user guidance
# Based on Script-Based Sequential Deployment Framework

# Source error handling if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/error-handling.sh" ]; then
    source "$SCRIPT_DIR/error-handling.sh"
fi

# Function to extract step number from script name
get_step_number() {
    local script_name="$1"
    echo "$script_name" | grep -oE 'step-[0-9]+' | grep -oE '[0-9]+'
}

# Function to detect the next step in sequence
detect_next_step() {
    local current_script="$1"
    local script_dir="${2:-$(dirname "$current_script")}"
    local current_number=$(get_step_number "$(basename "$current_script")")
    
    if [ -z "$current_number" ]; then
        return 1
    fi
    
    # Look for the next numbered step
    local next_number=$((current_number + 1))
    local next_pattern="step-$(printf "%03d" $next_number)-*.sh"
    
    # Find exact next step first
    local next_step=$(find "$script_dir" -name "$next_pattern" -type f 2>/dev/null | head -1)
    
    # If not found, look for any step with a higher number
    if [ -z "$next_step" ]; then
        for i in {2..50}; do
            next_number=$((current_number + i))
            next_pattern="step-$(printf "%03d" $next_number)-*.sh"
            next_step=$(find "$script_dir" -name "$next_pattern" -type f 2>/dev/null | head -1)
            if [ -n "$next_step" ]; then
                break
            fi
        done
    fi
    
    echo "$next_step"
}

# Function to get step description from script comments
get_step_description() {
    local script_path="$1"
    
    if [ -f "$script_path" ]; then
        # Look for description in first few lines of script
        local description=$(head -10 "$script_path" | grep -E "^# Purpose:|^# Description:|^# -" | head -1 | sed 's/^# //' | sed 's/^- //' | sed 's/Purpose: //' | sed 's/Description: //')
        
        if [ -z "$description" ]; then
            # Fallback: use script name
            description=$(basename "$script_path" | sed 's/step-[0-9]*-//' | sed 's/.sh$//' | sed 's/-/ /g')
        fi
        
        echo "$description"
    fi
}

# Function to show next step with description
show_next_step() {
    local current_script="$1"
    local script_dir="${2:-$(dirname "$current_script")}"
    
    echo -e "\n${GREEN}======================================${NC}"
    echo -e "${GREEN}🎯 NEXT STEP${NC}"
    echo -e "${GREEN}======================================${NC}"
    
    local next_step=$(detect_next_step "$current_script" "$script_dir")
    
    if [ -n "$next_step" ]; then
        local next_script_name=$(basename "$next_step")
        local description=$(get_step_description "$next_step")
        
        echo -e "${BLUE}Run:${NC} ./scripts/$next_script_name"
        echo -e "${CYAN}Purpose:${NC} $description"
    else
        # Special handling for last steps
        local current_number=$(get_step_number "$(basename "$current_script")")
        
        case "$current_number" in
            342)
                echo -e "${GREEN}✅ Smart Router deployment complete!${NC}"
                echo -e "${CYAN}Your transcription router is now ready to use.${NC}"
                echo -e "\n${BLUE}Optional next steps:${NC}"
                echo -e "- Deploy FastAPI server: ./scripts/step-301-fast-api-setup-ecr-repository.sh"
                echo -e "- Monitor system: ./scripts/monitor-smart.sh"
                echo -e "- Test the system: Send test events to EventBridge"
                ;;
            330)
                echo -e "${GREEN}✅ FastAPI server setup complete!${NC}"
                echo -e "${CYAN}Your GPU-accelerated transcription server is ready.${NC}"
                echo -e "\n${BLUE}Next steps:${NC}"
                echo -e "- Deploy Lambda router: ./scripts/step-340-deploy-lambda-router.sh"
                echo -e "- Or test directly: ./scripts/test-fast-api-s3.sh"
                ;;
            999)
                echo -e "${GREEN}✅ Cleanup complete!${NC}"
                echo -e "${CYAN}All resources have been removed.${NC}"
                echo -e "\n${BLUE}To redeploy:${NC}"
                echo -e "- Run: ./scripts/step-000-setup-configuration.sh"
                ;;
            *)
                echo -e "${YELLOW}No next step found. This might be the last step.${NC}"
                echo -e "${BLUE}Check README.md for more information.${NC}"
                ;;
        esac
    fi
}

# Function to validate prerequisites for a step
validate_prerequisites() {
    local script_name="$1"
    local script_dir="${2:-$(dirname "$script_name")}"
    
    # Extract step number
    local step_number=$(get_step_number "$(basename "$script_name")")
    
    if [ -z "$step_number" ]; then
        return 0  # Can't validate without step number
    fi
    
    # Define prerequisite mappings
    case "$step_number" in
        000)
            # No prerequisites for initial setup
            return 0
            ;;
        001)
            # No prerequisites for preflight check
            return 0
            ;;
        010)
            # IAM setup requires configuration
            if [ ! -f ".env" ]; then
                log_error "Configuration file .env not found" "prerequisite-check"
                echo -e "${YELLOW}💡 Run: ./scripts/step-000-setup-configuration.sh${NC}"
                return 1
            fi
            ;;
        011)
            # IAM validation requires IAM setup
            if ! is_step_completed "step-010"; then
                log_error "IAM setup not completed" "prerequisite-check"
                echo -e "${YELLOW}💡 Run: ./scripts/step-010-setup-iam-permissions.sh${NC}"
                return 1
            fi
            ;;
        020)
            # SQS requires IAM
            if ! is_step_completed "step-010"; then
                log_error "IAM setup not completed" "prerequisite-check"
                echo -e "${YELLOW}💡 Run: ./scripts/step-010-setup-iam-permissions.sh${NC}"
                return 1
            fi
            ;;
        340)
            # Lambda router requires SQS
            if [ -z "$QUEUE_URL" ] && [ -f ".env" ]; then
                source .env
            fi
            if [ -z "$QUEUE_URL" ]; then
                log_error "SQS queue not configured" "prerequisite-check"
                echo -e "${YELLOW}💡 Run: ./scripts/step-020-create-sqs-resources.sh${NC}"
                return 1
            fi
            ;;
        341)
            # EventBridge trigger requires Lambda
            if [ -z "$TRANSCRIPTION_ROUTER_FUNCTION_NAME" ] && [ -f ".env" ]; then
                source .env
            fi
            if [ -z "$TRANSCRIPTION_ROUTER_FUNCTION_NAME" ]; then
                log_error "Lambda router not deployed" "prerequisite-check"
                echo -e "${YELLOW}💡 Run: ./scripts/step-340-deploy-lambda-router.sh${NC}"
                return 1
            fi
            ;;
    esac
    
    return 0
}

# Function to show step purpose/description
show_step_purpose() {
    local script_name="$1"
    
    # Get description
    local description=$(get_step_description "$script_name")
    
    if [ -n "$description" ]; then
        echo -e "${CYAN}📋 Purpose: ${description}${NC}"
        echo
    fi
}

# Function to check if running in correct order
check_step_order() {
    local current_step="$1"
    local step_number=$(get_step_number "$(basename "$current_step")")
    
    # Check if any higher numbered steps have been completed
    if [ -d ".deployment-state" ]; then
        for status_file in .deployment-state/step-*.status; do
            if [ -f "$status_file" ]; then
                local completed_step=$(basename "$status_file" .status)
                local completed_number=$(get_step_number "$completed_step")
                
                if [ -n "$completed_number" ] && [ -n "$step_number" ] && [ "$completed_number" -gt "$step_number" ]; then
                    log_warning "Step $completed_step was already completed. Running steps out of order." "step-order-check"
                fi
            fi
        done
    fi
}

# Export functions for use in other scripts
export -f get_step_number
export -f detect_next_step
export -f get_step_description
export -f show_next_step
export -f validate_prerequisites
export -f show_step_purpose
export -f check_step_order

# Log successful load
if declare -f log_info > /dev/null 2>&1; then
    log_info "Step navigation library loaded successfully" "step-navigation.sh"
fi