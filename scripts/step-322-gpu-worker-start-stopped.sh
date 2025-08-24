#!/bin/bash
# step-322-gpu-worker-start-stopped.sh - Start existing stopped GPU workers
# Purpose: Start existing stopped GPU workers with cost analysis and confirmation

# Source navigation and error handling functions
source "$(dirname "$0")/step-navigation.sh" 2>/dev/null || {
    echo "Warning: Navigation functions not found"
}

source "$(dirname "$0")/error-handling.sh" 2>/dev/null || {
    echo "Warning: Error handling functions not found"
    set -e
}

# Initialize error handling
SCRIPT_NAME="step-322-gpu-worker-start-stopped"
setup_error_handling "$SCRIPT_NAME" 2>/dev/null || true

log_info "Starting GPU Worker Start Process" "$SCRIPT_NAME" 2>/dev/null || echo "🚀 Starting GPU Worker Start Process"

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
echo -e "${BLUE}🚀 Start Stopped GPU Workers${NC}"
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

# Find stopped GPU worker instances
echo -e "${CYAN}🔍 Finding stopped GPU worker instances...${NC}"

STOPPED_INSTANCES=$(aws ec2 describe-instances \
    --filters "Name=tag:Type,Values=fast-api-worker,gpu-worker,production-worker" \
              "Name=instance-state-name,Values=stopped" \
    --region "$REGION" \
    --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,Tags[?Key==`Name`].Value | [0],LaunchTime]' \
    --output json 2>/dev/null || echo '[]')

if [ "$(echo "$STOPPED_INSTANCES" | jq '. | length')" -eq 0 ]; then
    echo -e "${YELLOW}No stopped GPU worker instances found${NC}"
    echo ""
    echo "Options:"
    echo "  • Check running workers: ./step-321-gpu-worker-status.sh"
    echo "  • Launch new workers: ./step-320-fast-api-launch-gpu-instances.sh"
    echo ""
    exit 0
fi

# Display stopped instances
echo ""
echo -e "${GREEN}📋 Found stopped GPU workers:${NC}"
echo "┌─────┬────────────────────────┬─────────────────┬─────────────────┬──────────────┬──────────────┐"
echo "│ #   │ Name                   │ Instance ID     │ Type            │ Last Launch  │ Cost/Hour    │"
echo "├─────┼────────────────────────┼─────────────────┼─────────────────┼──────────────┼──────────────┤"

counter=0
declare -a instance_ids
declare -a instance_names
declare -a instance_types
declare -a instance_costs

echo "$STOPPED_INSTANCES" | jq -r '.[][] | @tsv' | while IFS=$'\t' read -r instance_id instance_type name launch_time; do
    [ "$name" = "null" ] && name="unnamed"
    [ -z "$name" ] && name="unnamed"
    
    # Truncate long names
    if [ ${#name} -gt 22 ]; then
        name="${name:0:19}..."
    fi
    
    hourly_cost=$(get_hourly_cost "$instance_type")
    last_launch=$(date -d "$launch_time" '+%m/%d %H:%M' 2>/dev/null || echo "Unknown")
    
    printf "│ %-3d │ %-22s │ %-15s │ %-15s │ %-12s │ \$%-11s │\n" \
        "$counter" "$name" "$instance_id" "$instance_type" "$last_launch" "$hourly_cost"
    
    # Store for later use (this runs in subshell, so we need to handle this differently)
    echo "$counter:$instance_id:$name:$instance_type:$hourly_cost" >> /tmp/worker-instances.txt
    counter=$((counter + 1))
done

echo "└─────┴────────────────────────┴─────────────────┴─────────────────┴──────────────┴──────────────┘"

# Read the stored data
declare -a instance_data
if [ -f /tmp/worker-instances.txt ]; then
    while IFS=':' read -r num id name type cost; do
        instance_data[$num]="$id:$name:$type:$cost"
    done < /tmp/worker-instances.txt
    rm -f /tmp/worker-instances.txt
fi

# Selection prompt
echo ""
echo -e "${YELLOW}Select workers to start:${NC}"
echo "  • Enter specific numbers (e.g., '0,2,3' or '0 2 3')"
echo "  • Enter 'all' to start all workers"
echo "  • Enter 'quit' to cancel"
echo ""

read -p "Your selection: " selection

case "$selection" in
    "quit"|"q"|"exit")
        echo "Operation cancelled"
        exit 0
        ;;
    "all"|"*")
        # Start all instances
        echo ""
        echo -e "${YELLOW}Starting all stopped GPU workers...${NC}"
        
        selected_instances=""
        selected_cost=0
        for i in "${!instance_data[@]}"; do
            IFS=':' read -r id name type cost <<< "${instance_data[$i]}"
            selected_instances="$selected_instances $id"
            selected_cost=$(echo "$selected_cost + $cost" | bc -l 2>/dev/null || echo "$selected_cost")
        done
        ;;
    *)
        # Parse selection
        selected_instances=""
        selected_cost=0
        
        # Handle comma or space separated
        selection=$(echo "$selection" | tr ',' ' ')
        
        for num in $selection; do
            if [[ "$num" =~ ^[0-9]+$ ]] && [ -n "${instance_data[$num]}" ]; then
                IFS=':' read -r id name type cost <<< "${instance_data[$num]}"
                selected_instances="$selected_instances $id"
                selected_cost=$(echo "$selected_cost + $cost" | bc -l 2>/dev/null || echo "$selected_cost")
                echo "  Selected: $name ($id) - \$$cost/hour"
            else
                echo -e "${RED}Invalid selection: $num${NC}"
                exit 1
            fi
        done
        ;;
esac

if [ -z "$selected_instances" ]; then
    echo -e "${RED}No valid instances selected${NC}"
    exit 1
fi

# Cost warning
echo ""
echo -e "${YELLOW}⚠️  Cost Impact:${NC}"
printf "Selected instances will cost: \$%.2f/hour\n" "$selected_cost"
printf "Estimated daily cost: \$%.2f\n" "$(echo "$selected_cost * 24" | bc -l)"
printf "Estimated monthly cost: \$%.2f\n" "$(echo "$selected_cost * 24 * 30" | bc -l)"

echo ""
read -p "Continue with starting these instances? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Operation cancelled"
    exit 0
fi

# Start the instances
echo ""
echo -e "${YELLOW}Starting selected GPU workers...${NC}"

for instance_id in $selected_instances; do
    echo "Starting $instance_id..."
    aws ec2 start-instances --instance-ids "$instance_id" --region "$REGION" >/dev/null 2>&1
    echo -e "  ${GREEN}✅ Start command sent${NC}"
done

echo ""
echo -e "${BLUE}⏳ Waiting for instances to reach running state...${NC}"
echo "This may take 1-2 minutes..."

# Wait for instances to be running
aws ec2 wait instance-running --instance-ids $selected_instances --region "$REGION"

echo -e "${GREEN}✅ All selected instances are now running!${NC}"

# Get updated instance information with IPs
echo ""
echo -e "${CYAN}📋 Updated instance information:${NC}"

RUNNING_INFO=$(aws ec2 describe-instances \
    --instance-ids $selected_instances \
    --region "$REGION" \
    --query 'Reservations[*].Instances[*].[InstanceId,PublicIpAddress,PrivateIpAddress,InstanceType,Tags[?Key==`Name`].Value | [0]]' \
    --output json)

echo "┌────────────────────────┬─────────────────┬──────────────┬──────────────┬─────────────────┐"
echo "│ Name                   │ Instance ID     │ Public IP    │ Private IP   │ Type            │"
echo "├────────────────────────┼─────────────────┼──────────────┼──────────────┼─────────────────┤"

echo "$RUNNING_INFO" | jq -r '.[][] | @tsv' | while IFS=$'\t' read -r instance_id public_ip private_ip instance_type name; do
    [ "$public_ip" = "null" ] && public_ip="(pending)"
    [ "$private_ip" = "null" ] && private_ip="(pending)"
    [ "$name" = "null" ] && name="unnamed"
    
    if [ ${#name} -gt 22 ]; then
        name="${name:0:19}..."
    fi
    
    printf "│ %-22s │ %-15s │ %-12s │ %-12s │ %-15s │\n" \
        "$name" "$instance_id" "$public_ip" "$private_ip" "$instance_type"
done

echo "└────────────────────────┴─────────────────┴──────────────┴──────────────┴─────────────────┘"

echo ""
echo -e "${BLUE}🎯 Next Steps:${NC}"
echo "1. Wait ~30 seconds for full system initialization"
echo "2. Deploy idle monitoring: ./step-323-gpu-worker-deploy-idle-monitor.sh"
echo "3. Check worker health: ./step-324-gpu-worker-health-check.sh"
echo "4. View all workers: ./step-321-gpu-worker-status.sh"

echo ""
echo -e "${GREEN}✅ GPU workers started successfully!${NC}"
echo -e "${BLUE}=======================================${NC}"

# Mark as completed and show next step
create_checkpoint "$SCRIPT_NAME" "completed" "$SCRIPT_NAME" 2>/dev/null || true
log_info "GPU Worker Start Process completed" "$SCRIPT_NAME" 2>/dev/null || echo "✅ GPU Worker Start Process completed"

# Show next step
if declare -f show_next_step > /dev/null; then
    show_next_step "$(basename "$0")" "$(dirname "$0")"
else
    echo -e "${BLUE}Next: Deploy idle monitoring with step-323-gpu-worker-deploy-idle-monitor.sh${NC}"
fi