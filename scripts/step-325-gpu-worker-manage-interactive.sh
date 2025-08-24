#!/bin/bash
# step-325-gpu-worker-manage-interactive.sh - Interactive menu for all worker operations

set -e

# Source configuration
if [ -f ".env" ]; then
    source .env
else
    echo "❌ .env file not found. Run step-000-setup-configuration.sh first."
    exit 1
fi

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Function to show menu
show_menu() {
    clear
    echo -e "${BLUE}=======================================${NC}"
    echo -e "${BLUE}🎛️  GPU Worker Management Console${NC}"
    echo -e "${BLUE}=======================================${NC}"
    echo ""
    echo -e "${CYAN}📊 Status & Information:${NC}"
    echo "  1) Show worker status and costs"
    echo "  2) Health check all workers"
    echo ""
    echo -e "${CYAN}🚀 Start & Deploy:${NC}"
    echo "  3) Start stopped workers"
    echo "  4) Launch new GPU workers"
    echo "  5) Deploy idle monitoring (auto-shutdown)"
    echo ""
    echo -e "${CYAN}🛑 Stop & Control:${NC}"
    echo "  6) Stop all running workers (save money)"
    echo "  7) Disable idle monitoring on workers"
    echo ""
    echo -e "${CYAN}🔧 Testing & Troubleshooting:${NC}"
    echo "  8) Test transcription on workers"
    echo "  9) View worker logs"
    echo "  10) SSH into worker"
    echo ""
    echo -e "${CYAN}💸 Cost Management:${NC}"
    echo "  11) Show cost analysis"
    echo "  12) Set idle timeout"
    echo ""
    echo -e "${CYAN}🔄 Other:${NC}"
    echo "  13) Refresh this menu"
    echo "  0) Exit"
    echo ""
    echo -e "${BLUE}=======================================${NC}"
}

# Function to get current cost summary
show_cost_summary() {
    echo -e "${CYAN}💰 Current Cost Summary:${NC}"
    
    RUNNING_INSTANCES=$(aws ec2 describe-instances \
        --filters "Name=tag:Type,Values=fast-api-worker,gpu-worker,production-worker" \
                  "Name=instance-state-name,Values=running" \
        --region "${AWS_REGION:-us-east-2}" \
        --query 'Reservations[*].Instances[*].InstanceType' \
        --output text 2>/dev/null | wc -w)
    
    if [ "$RUNNING_INSTANCES" -eq 0 ]; then
        echo "  💚 No running workers - $0.00/hour"
    else
        echo "  ⚠️  $RUNNING_INSTANCES workers running - check option 1 for details"
    fi
    echo ""
}

# Function to execute menu choice
execute_choice() {
    local choice="$1"
    
    case $choice in
        1)
            echo -e "${YELLOW}Showing worker status...${NC}"
            ./step-321-gpu-worker-status.sh
            ;;
        2)
            echo -e "${YELLOW}Running health checks...${NC}"
            ./step-324-gpu-worker-health-check.sh
            ;;
        3)
            echo -e "${YELLOW}Starting stopped workers...${NC}"
            ./step-322-gpu-worker-start-stopped.sh
            ;;
        4)
            echo -e "${YELLOW}Launching new GPU workers...${NC}"
            ./step-320-fast-api-launch-gpu-instances.sh
            ;;
        5)
            echo -e "${YELLOW}Deploying idle monitoring...${NC}"
            ./step-323-gpu-worker-deploy-idle-monitor.sh
            ;;
        6)
            echo -e "${YELLOW}Stopping all workers...${NC}"
            ./step-328-gpu-worker-stop-all.sh
            ;;
        7)
            disable_idle_monitoring
            ;;
        8)
            echo -e "${YELLOW}Testing transcription...${NC}"
            ./step-330-fast-api-test-transcription.sh 2>/dev/null || echo "Test script not available"
            ;;
        9)
            view_worker_logs
            ;;
        10)
            ssh_to_worker
            ;;
        11)
            detailed_cost_analysis
            ;;
        12)
            set_idle_timeout
            ;;
        13)
            return 0  # Just refresh menu
            ;;
        0)
            echo -e "${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice: $choice${NC}"
            ;;
    esac
}

# Function to disable idle monitoring
disable_idle_monitoring() {
    echo -e "${YELLOW}Finding workers with idle monitoring...${NC}"
    
    RUNNING_INSTANCES=$(aws ec2 describe-instances \
        --filters "Name=tag:Type,Values=fast-api-worker,gpu-worker,production-worker" \
                  "Name=instance-state-name,Values=running" \
        --region "${AWS_REGION:-us-east-2}" \
        --query 'Reservations[*].Instances[*].[InstanceId,PublicIpAddress,Tags[?Key==`Name`].Value | [0]]' \
        --output text 2>/dev/null)
    
    if [ -z "$RUNNING_INSTANCES" ]; then
        echo "No running workers found"
        return
    fi
    
    echo "Disabling idle monitoring on all running workers..."
    
    echo "$RUNNING_INSTANCES" | while read -r instance_id public_ip name; do
        if [ "$public_ip" != "None" ] && [ -n "$public_ip" ]; then
            echo "  Disabling on $name ($instance_id)..."
            ssh -i ~/.ssh/transcription-worker.pem -o StrictHostKeyChecking=no \
                ubuntu@$public_ip 'sudo systemctl stop gpu-idle-monitor' 2>/dev/null || echo "    Failed to disable"
        fi
    done
    
    echo -e "${GREEN}✅ Idle monitoring disabled${NC}"
}

# Function to view worker logs
view_worker_logs() {
    echo -e "${YELLOW}Select worker to view logs:${NC}"
    
    RUNNING_INSTANCES=$(aws ec2 describe-instances \
        --filters "Name=tag:Type,Values=fast-api-worker,gpu-worker,production-worker" \
                  "Name=instance-state-name,Values=running" \
        --region "${AWS_REGION:-us-east-2}" \
        --query 'Reservations[*].Instances[*].[InstanceId,PublicIpAddress,Tags[?Key==`Name`].Value | [0]]' \
        --output json 2>/dev/null)
    
    if [ "$(echo "$RUNNING_INSTANCES" | jq '. | length')" -eq 0 ]; then\n        echo "No running workers found"\n        return\n    fi\n    \n    counter=0\n    declare -a worker_ips\n    declare -a worker_names\n    \n    echo "$RUNNING_INSTANCES" | jq -r '.[][] | @tsv' | while IFS=$'\\t' read -r instance_id public_ip name; do\n        [ "$name" = "null" ] && name="unnamed"\n        echo "  $counter) $name ($instance_id) - $public_ip"\n        worker_ips[$counter]="$public_ip"\n        worker_names[$counter]="$name"\n        counter=$((counter + 1))\n    done\n    \n    echo ""\n    read -p "Select worker number: " worker_num\n    \n    if [[ "$worker_num" =~ ^[0-9]+$ ]]; then\n        # This is simplified - in practice you'd need to handle the array properly\n        echo "Feature not fully implemented - use SSH directly"\n        echo "Example: ssh -i ~/.ssh/transcription-worker.pem ubuntu@<worker-ip>"\n    fi\n}\n\n# Function to SSH into worker\nssh_to_worker() {\n    echo -e "${YELLOW}Select worker to SSH into:${NC}"\n    \n    RUNNING_INSTANCES=$(aws ec2 describe-instances \\\n        --filters "Name=tag:Type,Values=fast-api-worker,gpu-worker,production-worker" \\\n                  "Name=instance-state-name,Values=running" \\\n        --region "${AWS_REGION:-us-east-2}" \\\n        --query 'Reservations[*].Instances[*].[PublicIpAddress,Tags[?Key==`Name`].Value | [0]]' \\\n        --output text 2>/dev/null)\n    \n    if [ -z "$RUNNING_INSTANCES" ]; then\n        echo "No running workers found"\n        return\n    fi\n    \n    echo "$RUNNING_INSTANCES" | nl -v 0 | while read -r num ip name; do\n        [ "$name" = "None" ] && name="unnamed"\n        echo "  $num) $name - $ip"\n    done\n    \n    echo ""\n    read -p "Select worker number (or IP address): " selection\n    \n    # Simple IP detection\n    if [[ "$selection" =~ ^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$ ]]; then\n        echo "SSHing to $selection..."\n        ssh -i ~/.ssh/transcription-worker.pem ubuntu@$selection\n    else\n        echo "Please use direct IP address for now"\n        echo "Available IPs:"\n        echo "$RUNNING_INSTANCES" | awk '{print $1}' | grep -v None\n    fi\n}\n\n# Function for detailed cost analysis\ndetailed_cost_analysis() {\n    echo -e "${CYAN}💰 Detailed Cost Analysis${NC}"\n    echo ""\n    \n    INSTANCES_WITH_COSTS=$(aws ec2 describe-instances \\\n        --filters "Name=tag:Type,Values=fast-api-worker,gpu-worker,production-worker" \\\n        --region "${AWS_REGION:-us-east-2}" \\\n        --query 'Reservations[*].Instances[*].[InstanceId,State.Name,InstanceType,LaunchTime,Tags[?Key==`Name`].Value | [0]]' \\\n        --output json 2>/dev/null)\n    \n    total_running_cost=0\n    running_count=0\n    stopped_count=0\n    \n    echo "Instance breakdown:"\n    \n    echo "$INSTANCES_WITH_COSTS" | jq -r '.[][] | @tsv' | while IFS=$'\\t' read -r id state type launch name; do\n        [ "$name" = "null" ] && name="unnamed"\n        \n        case "$type" in\n            "g4dn.xlarge") cost="0.526" ;;\n            "g4dn.2xlarge") cost="0.752" ;;\n            "g5.xlarge") cost="1.006" ;;\n            "p3.2xlarge") cost="3.06" ;;\n            *) cost="0.50" ;;\n        esac\n        \n        if [ "$state" = "running" ]; then\n            running_count=$((running_count + 1))\n            total_running_cost=$(echo "$total_running_cost + $cost" | bc -l 2>/dev/null || echo "$total_running_cost")\n            echo "  🟢 $name ($type) - \\$$cost/hour - RUNNING"\n        else\n            stopped_count=$((stopped_count + 1))\n            echo "  ⭕ $name ($type) - \\$$cost/hour - STOPPED"\n        fi\n    done\n    \n    echo ""\n    echo "Summary:"\n    echo "  Running: $running_count instances"\n    echo "  Stopped: $stopped_count instances"\n    printf "  Current hourly cost: \\$%.2f\\n" "$total_running_cost"\n    printf "  Daily cost if unchanged: \\$%.2f\\n" "$(echo "$total_running_cost * 24" | bc -l)"\n    printf "  Monthly cost if unchanged: \\$%.2f\\n" "$(echo "$total_running_cost * 24 * 30" | bc -l)"\n}\n\n# Function to set idle timeout\nset_idle_timeout() {\n    echo -e "${YELLOW}Current idle timeout: ${GPU_WORKER_IDLE_TIMEOUT_MINUTES:-30} minutes${NC}"\n    echo ""\n    read -p "Enter new idle timeout in minutes (default: 30): " new_timeout\n    \n    new_timeout=${new_timeout:-30}\n    \n    if [[ "$new_timeout" =~ ^[0-9]+$ ]]; then\n        # Update .env file\n        if grep -q "GPU_WORKER_IDLE_TIMEOUT_MINUTES" .env; then\n            sed -i "s/^export GPU_WORKER_IDLE_TIMEOUT_MINUTES=.*/export GPU_WORKER_IDLE_TIMEOUT_MINUTES=\"$new_timeout\"/" .env\n        else\n            echo "export GPU_WORKER_IDLE_TIMEOUT_MINUTES=\"$new_timeout\"" >> .env\n        fi\n        \n        echo -e "${GREEN}✅ Idle timeout updated to $new_timeout minutes${NC}"\n        echo "Re-deploy idle monitoring to apply: option 5"\n    else\n        echo -e "${RED}Invalid timeout value${NC}"\n    fi\n}\n\n# Main loop\nwhile true; do\n    show_menu\n    show_cost_summary\n    \n    read -p "Select option (0-13): " choice\n    \n    echo ""\n    execute_choice "$choice"\n    \n    echo ""\n    echo -e "${BLUE}Press Enter to continue...${NC}"\n    read\ndone