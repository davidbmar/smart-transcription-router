#!/bin/bash

# step-325-wait-for-gpu-instance-ready.sh - Wait for GPU instance to be fully ready
# This script polls the Fast API instance until it's fully initialized and responsive
# Prerequisites: step-320 (GPU instance launched)
# Outputs: Confirmation that instance is ready for testing

# Source framework libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/error-handling.sh" ]; then
    source "$SCRIPT_DIR/error-handling.sh"
else
    echo "Error handling library not found, using basic error handling"
    set -e
fi

if [ -f "$SCRIPT_DIR/step-navigation.sh" ]; then
    source "$SCRIPT_DIR/step-navigation.sh"
fi

# Initialize script
SCRIPT_NAME="step-325-wait-for-gpu-instance-ready"
setup_error_handling "$SCRIPT_NAME"
create_checkpoint "$SCRIPT_NAME" "in_progress" "$SCRIPT_NAME"

# Show step purpose
if declare -f show_step_purpose > /dev/null 2>&1; then
    show_step_purpose "$0"
fi

# Load configuration
CONFIG_FILE=".env"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    log_info "Configuration loaded" "$SCRIPT_NAME"
else
    log_error "Configuration file not found" "$SCRIPT_NAME"
    exit 1
fi

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}⏳ Wait for GPU Instance Ready${NC}"
echo -e "${BLUE}======================================${NC}"
echo

# Function to find the most recent Fast API instance
find_latest_instance() {
    aws ec2 describe-instances \
        --filters "Name=tag:Type,Values=fast-api-worker" "Name=instance-state-name,Values=running" \
        --query 'Reservations[*].Instances[*].[InstanceId,PublicIpAddress,LaunchTime]' \
        --output text \
        --region "$AWS_REGION" | \
    sort -k3 -r | head -1
}

# Function to check if instance is ready
check_instance_ready() {
    local ip="$1"
    local checks_passed=0
    local total_checks=4
    
    # Check 1: SSH connectivity
    if ssh -i "${KEY_NAME}.pem" -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@"$ip" 'echo "SSH OK"' >/dev/null 2>&1; then
        ((checks_passed++))
        echo "  ✅ SSH connectivity"
    else
        echo "  ❌ SSH connectivity"
        return 1
    fi
    
    # Check 2: Docker container running
    local container_status=$(ssh -i "${KEY_NAME}.pem" -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@"$ip" 'docker ps --filter name=fast-api-gpu --format "{{.Status}}"' 2>/dev/null)
    if [[ "$container_status" == *"Up"* ]]; then
        ((checks_passed++))
        echo "  ✅ Docker container running"
    else
        echo "  ❌ Docker container (Status: ${container_status:-Not found})"
        return 1
    fi
    
    # Check 3: API health endpoint
    if curl -s --connect-timeout 5 "http://$ip:8000/health" >/dev/null 2>&1; then
        ((checks_passed++))
        echo "  ✅ API health endpoint"
    else
        echo "  ❌ API health endpoint"
        return 1
    fi
    
    # Check 4: GPU access in container
    local gpu_status=$(ssh -i "${KEY_NAME}.pem" -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@"$ip" 'docker exec fast-api-gpu nvidia-smi --query-gpu=name --format=csv,noheader,nounits 2>/dev/null | head -1' 2>/dev/null)
    if [ -n "$gpu_status" ]; then
        ((checks_passed++))
        echo "  ✅ GPU access (${gpu_status})"
    else
        echo "  ❌ GPU access"
        return 1
    fi
    
    # All checks passed
    if [ $checks_passed -eq $total_checks ]; then
        return 0
    else
        return 1
    fi
}

# Function to show setup progress
show_setup_progress() {
    local ip="$1"
    echo "📋 Setup Progress:"
    
    # Show last few lines of setup log
    local setup_log=$(ssh -i "${KEY_NAME}.pem" -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@"$ip" 'sudo tail -3 /var/log/fast-api-setup.log 2>/dev/null | grep -E "^\[" | tail -1' 2>/dev/null)
    if [ -n "$setup_log" ]; then
        echo "  Latest: $setup_log"
    fi
    
    # Show Docker status
    local docker_status=$(ssh -i "${KEY_NAME}.pem" -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@"$ip" 'docker ps -a --filter name=fast-api-gpu --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"' 2>/dev/null)
    if [ -n "$docker_status" ]; then
        echo "$docker_status" | sed 's/^/  /'
    fi
}

# Find the latest instance
log_info "Finding most recent Fast API instance..." "$SCRIPT_NAME"
instance_info=$(find_latest_instance)

if [ -z "$instance_info" ]; then
    log_error "No running Fast API instances found" "$SCRIPT_NAME"
    echo -e "${YELLOW}💡 Run: ./scripts/step-320-fast-api-launch-gpu-instances.sh${NC}"
    exit 1
fi

# Parse instance information
INSTANCE_ID=$(echo "$instance_info" | awk '{print $1}')
PUBLIC_IP=$(echo "$instance_info" | awk '{print $2}')
LAUNCH_TIME=$(echo "$instance_info" | awk '{print $3}')

echo -e "${GREEN}[MONITORING]${NC}"
echo "Instance ID: $INSTANCE_ID"
echo "Public IP: $PUBLIC_IP"
echo "Launch Time: $LAUNCH_TIME"
echo

# Check if key file exists
if [ ! -f "${KEY_NAME}.pem" ]; then
    log_error "SSH key file not found: ${KEY_NAME}.pem" "$SCRIPT_NAME"
    echo -e "${YELLOW}💡 Make sure your SSH key is in the current directory${NC}"
    exit 1
fi

# Main polling loop
MAX_WAIT_MINUTES=15
POLL_INTERVAL=60  # 1 minute
START_TIME=$(date +%s)
ATTEMPT=1

log_info "Waiting for instance to be fully ready (max ${MAX_WAIT_MINUTES} minutes)..." "$SCRIPT_NAME"
echo -e "${YELLOW}Press Ctrl+C to stop waiting${NC}"
echo

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED_MINUTES=$(( (CURRENT_TIME - START_TIME) / 60 ))
    
    echo -e "${BLUE}[ATTEMPT $ATTEMPT - ${ELAPSED_MINUTES}m elapsed]${NC}"
    
    if check_instance_ready "$PUBLIC_IP"; then
        echo
        log_success "Instance is fully ready!" "$SCRIPT_NAME"
        break
    else
        if [ $ELAPSED_MINUTES -ge $MAX_WAIT_MINUTES ]; then
            echo
            log_error "Timeout after ${MAX_WAIT_MINUTES} minutes" "$SCRIPT_NAME"
            echo -e "${YELLOW}💡 You can manually check: ssh -i ${KEY_NAME}.pem ubuntu@${PUBLIC_IP}${NC}"
            exit 1
        fi
        
        echo
        show_setup_progress "$PUBLIC_IP"
        echo
        log_info "Not ready yet. Waiting ${POLL_INTERVAL} seconds... (${ELAPSED_MINUTES}/${MAX_WAIT_MINUTES} min)" "$SCRIPT_NAME"
        sleep $POLL_INTERVAL
        ((ATTEMPT++))
    fi
done

echo
echo -e "${BLUE}======================================${NC}"
echo -e "${GREEN}✅ GPU Instance Ready for Testing${NC}"
echo -e "${BLUE}======================================${NC}"
echo
echo -e "${GREEN}[INSTANCE READY]${NC}"
echo "Instance ID: $INSTANCE_ID"
echo "Public IP: $PUBLIC_IP"
echo "API URL: http://$PUBLIC_IP:8000"
echo "Health: http://$PUBLIC_IP:8000/health"
echo "Docs: http://$PUBLIC_IP:8000/docs"
echo
echo -e "${GREEN}[QUICK TEST]${NC}"
echo "curl -s http://$PUBLIC_IP:8000/health | jq"
echo

# Mark step as completed
create_checkpoint "$SCRIPT_NAME" "completed" "$SCRIPT_NAME"
log_success "GPU instance is ready for testing" "$SCRIPT_NAME"

# Show next step using navigation library
if declare -f show_next_step > /dev/null 2>&1; then
    show_next_step "$0" "$(dirname "$0")"
else
    echo ""
    log_info "Next step: Run ./scripts/step-326-fast-api-check-gpu-health.sh" "$SCRIPT_NAME"
fi