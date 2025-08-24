#!/bin/bash
# step-321-gpu-worker-status.sh - Show all GPU worker status (running/stopped/costs)
# Purpose: Display comprehensive status and cost analysis for all GPU worker instances

# Source navigation and error handling functions
source "$(dirname "$0")/step-navigation.sh" 2>/dev/null || {
    echo "Warning: Navigation functions not found"
}

source "$(dirname "$0")/error-handling.sh" 2>/dev/null || {
    echo "Warning: Error handling functions not found"
    set -e
}

# Initialize error handling
SCRIPT_NAME="step-321-gpu-worker-status"
setup_error_handling "$SCRIPT_NAME" 2>/dev/null || true

log_info "Starting GPU Worker Status Check" "$SCRIPT_NAME" 2>/dev/null || echo "🖥️ Starting GPU Worker Status Check"

# Create checkpoint
create_checkpoint "$SCRIPT_NAME" "in_progress" "$SCRIPT_NAME" 2>/dev/null || true

# Load configuration
CONFIG_FILE=".env"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    log_error "Configuration file not found." "$SCRIPT_NAME" 2>/dev/null || echo "❌ .env file not found. Run step-000-setup-configuration.sh first."
    create_checkpoint "$SCRIPT_NAME" "failed" "$SCRIPT_NAME" 2>/dev/null || true
    exit 1
fi

echo -e "${BLUE}=======================================${NC}"
echo -e "${BLUE}🖥️  GPU Worker Status Dashboard${NC}"
echo -e "${BLUE}=======================================${NC}"
echo ""

REGION=${AWS_REGION:-us-east-2}

# Function to get hourly cost for instance type
get_hourly_cost() {
    local instance_type="$1"
    case "$instance_type" in
        "g4dn.xlarge") echo "0.526" ;;
        "g4dn.2xlarge") echo "0.752" ;;
        "g4dn.4xlarge") echo "1.204" ;;
        "g5.xlarge") echo "1.006" ;;
        "g5.2xlarge") echo "1.212" ;;
        "p3.2xlarge") echo "3.06" ;;
        "p3.8xlarge") echo "12.24" ;;
        "p4d.24xlarge") echo "32.77" ;;
        *) echo "0.50" ;;  # Default estimate
    esac
}

# Function to calculate uptime
calculate_uptime() {
    local launch_time="$1"
    local current_time=$(date -u +%s)
    local launch_timestamp=$(date -d "$launch_time" +%s 2>/dev/null || echo "0")
    
    if [ "$launch_timestamp" -eq 0 ]; then
        echo "Unknown"
        return
    fi
    
    local uptime_seconds=$((current_time - launch_timestamp))
    local hours=$((uptime_seconds / 3600))
    local minutes=$(((uptime_seconds % 3600) / 60))
    
    if [ $hours -gt 0 ]; then
        echo "${hours}h ${minutes}m"
    else
        echo "${minutes}m"
    fi
}

# Get all GPU worker instances
echo -e "${CYAN}🔍 Scanning for GPU worker instances...${NC}"

INSTANCES_JSON=$(aws ec2 describe-instances \
    --filters "Name=tag:Type,Values=fast-api-worker,gpu-worker,production-worker" \
    --region "$REGION" \
    --query 'Reservations[*].Instances[*].[InstanceId,State.Name,InstanceType,PublicIpAddress,LaunchTime,Tags[?Key==`Name`].Value | [0],PrivateIpAddress]' \
    --output json 2>/dev/null || echo '[]')

if [ "$(echo "$INSTANCES_JSON" | jq '. | length')" -eq 0 ]; then
    echo -e "${YELLOW}No GPU worker instances found${NC}"
    echo ""
    echo "To create GPU workers, run:"
    echo "  ./step-320-fast-api-launch-gpu-instances.sh"
    echo ""
    exit 0
fi

# Parse and display instances
running_count=0
stopped_count=0
total_hourly_cost=0

echo ""
echo -e "${GREEN}📊 Instance Status:${NC}"
echo "┌────────────────────────┬─────────────┬──────────────┬─────────────────┬──────────────┬─────────────┬──────────────┐"
echo "│ Name                   │ Instance ID │ State        │ Type            │ Public IP    │ Uptime      │ $/hour       │"
echo "├────────────────────────┼─────────────┼──────────────┼─────────────────┼──────────────┼─────────────┼──────────────┤"

echo "$INSTANCES_JSON" | jq -r '.[][] | @tsv' | while IFS=$'\t' read -r instance_id state instance_type public_ip launch_time name private_ip; do
    # Handle null values
    [ "$public_ip" = "null" ] && public_ip="-"
    [ "$private_ip" = "null" ] && private_ip="-"
    [ "$name" = "null" ] && name="unnamed"
    [ -z "$name" ] && name="unnamed"
    
    # Calculate costs and uptime
    hourly_cost=$(get_hourly_cost "$instance_type")
    uptime=$(calculate_uptime "$launch_time")
    
    # Color code state
    case "$state" in
        "running")
            state_colored="\e[32mrunning\e[0m"
            running_count=$((running_count + 1))
            total_hourly_cost=$(echo "$total_hourly_cost + $hourly_cost" | bc -l 2>/dev/null || echo "$total_hourly_cost")
            ;;
        "stopped")
            state_colored="\e[33mstopped\e[0m"
            stopped_count=$((stopped_count + 1))
            uptime="-"
            ;;
        "stopping"|"pending"|"shutting-down")
            state_colored="\e[31m$state\e[0m"
            ;;
        *)
            state_colored="$state"
            ;;
    esac
    
    # Truncate long names
    if [ ${#name} -gt 22 ]; then
        name="${name:0:19}..."
    fi
    
    printf "│ %-22s │ %-11s │ %-12s │ %-15s │ %-12s │ %-11s │ \$%-11s │\n" \
        "$name" "$instance_id" "$state_colored" "$instance_type" "$public_ip" "$uptime" "$hourly_cost"
done

echo "└────────────────────────┴─────────────┴──────────────┴─────────────────┴──────────────┴─────────────┴──────────────┘"

# Cost summary
echo ""
echo -e "${CYAN}💰 Cost Analysis:${NC}"
echo "Running instances: $running_count"
echo "Stopped instances: $stopped_count"

if [ "$(echo "$total_hourly_cost > 0" | bc -l 2>/dev/null)" = "1" ]; then
    daily_cost=$(echo "$total_hourly_cost * 24" | bc -l)
    monthly_cost=$(echo "$total_hourly_cost * 24 * 30" | bc -l)
    
    printf "Current hourly cost: \$%.2f\n" "$total_hourly_cost"
    printf "Estimated daily cost: \$%.2f\n" "$daily_cost"
    printf "Estimated monthly cost: \$%.2f\n" "$monthly_cost"
    
    if [ "$running_count" -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}⚠️  You have running GPU instances incurring costs!${NC}"
        echo "To stop all workers: ./step-328-gpu-worker-stop-all.sh"
    fi
else
    echo "Current hourly cost: $0.00 (all instances stopped)"
fi

# Check idle monitoring status
echo ""
echo -e "${CYAN}🔍 Idle Monitoring Status:${NC}"

if [ "$running_count" -gt 0 ]; then
    echo "Checking idle monitors on running instances..."
    
    echo "$INSTANCES_JSON" | jq -r '.[][] | select(.[1] == "running") | @tsv' | while IFS=$'\t' read -r instance_id state instance_type public_ip launch_time name private_ip; do
        if [ "$public_ip" != "null" ] && [ -n "$public_ip" ]; then
            echo -n "  $name ($instance_id): "
            
            # Check if idle monitor is running (with timeout)
            if timeout 5 ssh -i ~/.ssh/transcription-worker.pem -o StrictHostKeyChecking=no -o ConnectTimeout=3 ubuntu@$public_ip \
                'sudo systemctl is-active gpu-idle-monitor >/dev/null 2>&1' 2>/dev/null; then
                echo -e "${GREEN}✅ Idle monitor active${NC}"
            else
                echo -e "${RED}❌ No idle monitor${NC}"
                echo "    To deploy: ./step-323-gpu-worker-deploy-idle-monitor.sh"
            fi
        fi
    done
else
    echo "No running instances to check"
fi

# Quick actions
echo ""
echo -e "${BLUE}🚀 Quick Actions:${NC}"
echo "  Start stopped workers: ./step-322-gpu-worker-start-stopped.sh"
echo "  Deploy idle monitoring: ./step-323-gpu-worker-deploy-idle-monitor.sh"
echo "  Health check all workers: ./step-324-gpu-worker-health-check.sh"
echo "  Interactive management: ./step-325-gpu-worker-manage-interactive.sh"
echo "  Stop all workers: ./step-328-gpu-worker-stop-all.sh"

echo ""
echo -e "${BLUE}=======================================${NC}"

# Mark as completed and show next step
create_checkpoint "$SCRIPT_NAME" "completed" "$SCRIPT_NAME" 2>/dev/null || true
log_info "GPU Worker Status Check completed" "$SCRIPT_NAME" 2>/dev/null || echo "✅ GPU Worker Status Check completed"

# Show next step
if declare -f show_next_step > /dev/null; then
    show_next_step "$(basename "$0")" "$(dirname "$0")"
else
    echo -e "${BLUE}Next: Start workers with step-322-gpu-worker-start-stopped.sh${NC}"
fi