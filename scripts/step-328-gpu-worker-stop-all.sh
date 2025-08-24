#!/bin/bash
# step-328-gpu-worker-stop-all.sh - Stop all running GPU workers (cost savings)
# Purpose: Stop all running GPU workers to save costs while preserving instances for restart

# Source navigation and error handling functions
source "$(dirname "$0")/step-navigation.sh" 2>/dev/null || {
    echo "Warning: Navigation functions not found"
}

source "$(dirname "$0")/error-handling.sh" 2>/dev/null || {
    echo "Warning: Error handling functions not found"
    set -e
}

# Initialize error handling
SCRIPT_NAME="step-328-gpu-worker-stop-all"
setup_error_handling "$SCRIPT_NAME" 2>/dev/null || true

log_info "Starting GPU Worker Stop Process" "$SCRIPT_NAME" 2>/dev/null || echo "🛑 Starting GPU Worker Stop Process"

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
echo -e "${BLUE}🛑 Stop All GPU Workers${NC}"
echo -e "${BLUE}=======================================${NC}"

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
        *) echo "0.50" ;;
    esac
}

# Find running GPU worker instances
echo -e "${CYAN}🔍 Finding running GPU worker instances...${NC}"

RUNNING_INSTANCES=$(aws ec2 describe-instances \
    --filters "Name=tag:Type,Values=fast-api-worker,gpu-worker,production-worker" \
              "Name=instance-state-name,Values=running" \
    --region "$REGION" \
    --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,Tags[?Key==`Name`].Value | [0],LaunchTime]' \
    --output json 2>/dev/null || echo '[]')

if [ "$(echo "$RUNNING_INSTANCES" | jq '. | length')" -eq 0 ]; then
    echo -e "${GREEN}✅ No running GPU worker instances found${NC}"
    echo "All workers are already stopped - no costs being incurred"
    echo ""
    echo "To start workers:"
    echo "  ./step-322-gpu-worker-start-stopped.sh"
    echo ""
    exit 0
fi

# Calculate current costs
total_hourly_cost=0
running_count=0

# Display running instances and calculate costs
echo ""
echo -e "${YELLOW}⚠️  Running GPU workers (incurring costs):${NC}"
echo "┌────────────────────────┬─────────────────┬─────────────────┬───────────────┐"
echo "│ Name                   │ Instance ID     │ Type            │ Cost/Hour      │"
echo "├────────────────────────┼─────────────────┼─────────────────┼───────────────┤"

declare -a instance_ids
declare -a instance_names

echo "$RUNNING_INSTANCES" | jq -r '.[][] | @tsv' | while IFS=$'\t' read -r instance_id instance_type name launch_time; do
    [ "$name" = "null" ] && name="unnamed"
    [ -z "$name" ] && name="unnamed"
    
    # Truncate long names
    if [ ${#name} -gt 22 ]; then
        name="${name:0:19}..."
    fi
    
    hourly_cost=$(get_hourly_cost "$instance_type")
    total_hourly_cost=$(echo "$total_hourly_cost + $hourly_cost" | bc -l 2>/dev/null || echo "$total_hourly_cost")
    running_count=$((running_count + 1))
    
    printf "│ %-22s │ %-15s │ %-15s │ \$%-13s │\n" \
        "$name" "$instance_id" "$instance_type" "$hourly_cost"
    
    # Store instance info
    echo "$instance_id" >> /tmp/instances_to_stop.txt
    echo "$name" >> /tmp/instance_names.txt
done

echo "└────────────────────────┴─────────────────┴─────────────────┴───────────────┘"

# Cost analysis
echo ""
echo -e "${YELLOW}💰 Cost Impact Analysis:${NC}"
printf "Current hourly cost: \$%.2f\n" "$total_hourly_cost"
printf "Daily cost if left running: \$%.2f\n" "$(echo "$total_hourly_cost * 24" | bc -l)"
printf "Monthly cost if left running: \$%.2f\n" "$(echo "$total_hourly_cost * 24 * 30" | bc -l)"

echo ""
echo -e "${GREEN}💸 Savings by stopping all workers:${NC}"
printf "Per hour saved: \$%.2f\n" "$total_hourly_cost"
printf "Per day saved: \$%.2f\n" "$(echo "$total_hourly_cost * 24" | bc -l)"
printf "Per month saved: \$%.2f\n" "$(echo "$total_hourly_cost * 24 * 30" | bc -l)"

echo ""
echo -e "${RED}⚠️  WARNING: This will stop ALL running GPU workers${NC}"
echo "Workers can be restarted later with: ./step-322-gpu-worker-start-stopped.sh"
echo "No data will be lost (instances are stopped, not terminated)"
echo ""

# Confirmation
read -p "Stop all $running_count GPU workers to save costs? (y/N): " confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Operation cancelled - workers remain running"
    rm -f /tmp/instances_to_stop.txt /tmp/instance_names.txt
    exit 0
fi

# Stop all instances
echo ""
echo -e "${YELLOW}🛑 Stopping all GPU workers...${NC}"

if [ -f /tmp/instances_to_stop.txt ]; then
    instance_list=$(cat /tmp/instances_to_stop.txt | tr '\n' ' ')
    
    echo "Sending stop commands..."
    aws ec2 stop-instances --instance-ids $instance_list --region "$REGION" >/dev/null 2>&1
    
    echo -e "${GREEN}✅ Stop commands sent to all workers${NC}"
    echo ""
    echo -e "${BLUE}⏳ Waiting for instances to stop...${NC}"
    echo "This may take 1-2 minutes..."
    
    # Wait for instances to stop
    aws ec2 wait instance-stopped --instance-ids $instance_list --region "$REGION"
    
    echo -e "${GREEN}✅ All GPU workers have been stopped!${NC}"
fi

# Verify all stopped
echo ""
echo -e "${CYAN}🔍 Verifying all workers are stopped...${NC}"

STILL_RUNNING=$(aws ec2 describe-instances \
    --filters "Name=tag:Type,Values=fast-api-worker,gpu-worker,production-worker" \
              "Name=instance-state-name,Values=running" \
    --region "$REGION" \
    --query 'Reservations[*].Instances[*].[InstanceId]' \
    --output text 2>/dev/null | wc -l)

if [ "$STILL_RUNNING" -eq 0 ]; then
    echo -e "${GREEN}✅ Verified: All GPU workers are stopped${NC}"
    echo -e "${GREEN}✅ Cost savings activated!${NC}"
else
    echo -e "${YELLOW}⚠️  $STILL_RUNNING workers may still be stopping...${NC}"
fi

# Cleanup temp files
rm -f /tmp/instances_to_stop.txt /tmp/instance_names.txt

# Summary
echo ""
echo -e "${BLUE}=======================================${NC}"
echo -e "${BLUE}✅ GPU Workers Stopped Successfully${NC}"
echo -e "${BLUE}=======================================${NC}"
echo ""
printf "Cost savings: \$%.2f per hour\n" "$total_hourly_cost"
printf "Daily savings: \$%.2f\n" "$(echo "$total_hourly_cost * 24" | bc -l)"
echo ""
echo -e "${CYAN}🚀 To restart workers later:${NC}"
echo "  ./step-321-gpu-worker-status.sh          (view status)"
echo "  ./step-322-gpu-worker-start-stopped.sh   (start workers)"
echo "  ./step-323-gpu-worker-deploy-idle-monitor.sh (re-enable auto-shutdown)"

echo ""
echo -e "${GREEN}💰 Money saved! Workers can be restarted anytime.${NC}"
echo -e "${BLUE}=======================================${NC}"

# Mark as completed and show next step
create_checkpoint "$SCRIPT_NAME" "completed" "$SCRIPT_NAME" 2>/dev/null || true
log_info "GPU Worker Stop Process completed" "$SCRIPT_NAME" 2>/dev/null || echo "✅ GPU Worker Stop Process completed"

# Show next step
if declare -f show_next_step > /dev/null; then
    show_next_step "$(basename "$0")" "$(dirname "$0")"
else
    echo -e "${BLUE}Workers stopped. Check status anytime with step-321-gpu-worker-status.sh${NC}"
fi