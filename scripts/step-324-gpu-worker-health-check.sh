#!/bin/bash
# step-324-gpu-worker-health-check.sh - Comprehensive health check (GPU+API+Queue)
# Purpose: Perform comprehensive health checks on all GPU worker instances

# Source navigation and error handling functions
source "$(dirname "$0")/step-navigation.sh" 2>/dev/null || {
    echo "Warning: Navigation functions not found"
}

source "$(dirname "$0")/error-handling.sh" 2>/dev/null || {
    echo "Warning: Error handling functions not found"
    set -e
}

# Initialize error handling
SCRIPT_NAME="step-324-gpu-worker-health-check"
setup_error_handling "$SCRIPT_NAME" 2>/dev/null || true

log_info "Starting GPU Worker Health Check" "$SCRIPT_NAME" 2>/dev/null || echo "🏥 Starting GPU Worker Health Check"

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
echo -e "${BLUE}🏥 GPU Worker Health Check${NC}"
echo -e "${BLUE}=======================================${NC}"

REGION=${AWS_REGION:-us-east-2}
KEY_PATH=${KEY_PATH:-~/.ssh/transcription-worker.pem}

# Find running GPU worker instances
echo -e "${CYAN}🔍 Finding running GPU worker instances...${NC}"

INSTANCE_INFO=$(aws ec2 describe-instances \
    --filters "Name=tag:Type,Values=fast-api-worker,gpu-worker,production-worker" \
              "Name=instance-state-name,Values=running" \
    --region "$REGION" \
    --query 'Reservations[*].Instances[*].[InstanceId,PublicIpAddress,InstanceType,Tags[?Key==`Name`].Value | [0]]' \
    --output json 2>/dev/null || echo '[]')

if [ "$(echo "$INSTANCE_INFO" | jq '. | length')" -eq 0 ]; then
    echo -e "${RED}❌ No running GPU worker instances found${NC}"
    echo ""
    echo "Start workers first:"
    echo "  ./step-322-gpu-worker-start-stopped.sh"
    echo ""
    exit 1
fi

# Health check functions
check_ssh_connectivity() {
    local ip="$1"
    timeout 5 ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=3 \
        ubuntu@$ip 'echo connected' >/dev/null 2>&1
}

check_gpu_status() {
    local ip="$1"
    ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no ubuntu@$ip \
        'nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits' 2>/dev/null
}

check_docker_containers() {
    local ip="$1"
    ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no ubuntu@$ip \
        'docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"' 2>/dev/null
}

check_fastapi_health() {
    local ip="$1"
    ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no ubuntu@$ip \
        'curl -s --max-time 5 http://localhost:8000/health' 2>/dev/null
}

check_idle_monitor() {
    local ip="$1"
    ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no ubuntu@$ip \
        'sudo systemctl is-active gpu-idle-monitor 2>/dev/null && echo "active" || echo "inactive"' 2>/dev/null
}

check_system_resources() {
    local ip="$1"
    ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no ubuntu@$ip \
        'echo "CPU: $(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk "{print int(100 - \$1)}")% Memory: $(free | grep Mem | awk "{printf \"%.1f%%\", \$3/\$2 * 100.0}") Disk: $(df -h / | awk "NR==2{print \$5}")"' 2>/dev/null
}

# Perform health checks
echo ""
echo -e "${GREEN}🔧 Performing comprehensive health checks...${NC}"
echo ""

overall_health="healthy"
total_workers=0
healthy_workers=0

echo "$INSTANCE_INFO" | jq -r '.[][] | @tsv' | while IFS=$'\t' read -r instance_id public_ip instance_type instance_name; do
    [ "$public_ip" = "null" ] && public_ip="(no IP)"
    [ "$instance_name" = "null" ] && instance_name="unnamed"
    [ -z "$instance_name" ] && instance_name="unnamed"
    
    total_workers=$((total_workers + 1))
    worker_healthy=true
    
    echo -e "${CYAN}📋 Checking: $instance_name ($instance_id)${NC}"
    echo "  Instance Type: $instance_type"
    echo "  Public IP: $public_ip"
    
    if [ "$public_ip" = "(no IP)" ]; then
        echo -e "  ${RED}❌ No public IP - cannot perform checks${NC}"
        worker_healthy=false
    else
        # SSH Connectivity
        echo -n "  SSH Connection: "
        if check_ssh_connectivity "$public_ip"; then
            echo -e "${GREEN}✅${NC}"
        else
            echo -e "${RED}❌${NC}"
            worker_healthy=false
        fi
        
        if [ "$worker_healthy" = true ]; then
            # GPU Status
            echo -n "  GPU Status: "
            gpu_info=$(check_gpu_status "$public_ip")
            if [ -n "$gpu_info" ]; then
                echo -e "${GREEN}✅${NC}"
                echo "    $gpu_info"
            else
                echo -e "${RED}❌ No GPU detected${NC}"
                worker_healthy=false
            fi
            
            # Docker Containers
            echo -n "  Docker Containers: "
            containers=$(check_docker_containers "$public_ip")
            if echo "$containers" | grep -q "Up"; then
                echo -e "${GREEN}✅${NC}"
                echo "$containers" | tail -n +2 | sed 's/^/    /'
            else
                echo -e "${YELLOW}⚠️  No running containers${NC}"
            fi
            
            # FastAPI Health
            echo -n "  FastAPI Health: "
            api_response=$(check_fastapi_health "$public_ip")
            if echo "$api_response" | grep -q '"status".*"healthy"'; then
                echo -e "${GREEN}✅${NC}"
            else
                echo -e "${RED}❌ API not responding${NC}"
                worker_healthy=false
            fi
            
            # Idle Monitor
            echo -n "  Idle Monitor: "
            idle_status=$(check_idle_monitor "$public_ip")
            if [ "$idle_status" = "active" ]; then
                echo -e "${GREEN}✅ Active${NC}"
            else
                echo -e "${YELLOW}⚠️  Inactive${NC}"
            fi
            
            # System Resources
            echo -n "  System Resources: "
            resources=$(check_system_resources "$public_ip")
            if [ -n "$resources" ]; then
                echo -e "${GREEN}✅${NC}"
                echo "    $resources"
            else
                echo -e "${RED}❌ Cannot get system info${NC}"
            fi
        fi
    fi
    
    if [ "$worker_healthy" = true ]; then
        echo -e "  ${GREEN}✅ Overall: HEALTHY${NC}"
        healthy_workers=$((healthy_workers + 1))
    else
        echo -e "  ${RED}❌ Overall: UNHEALTHY${NC}"
        overall_health="unhealthy"
    fi
    
    echo ""
done

# Summary
echo -e "${BLUE}=======================================${NC}"
echo -e "${BLUE}📊 Health Check Summary${NC}"
echo -e "${BLUE}=======================================${NC}"
echo ""
echo "Total workers: $total_workers"
echo "Healthy workers: $healthy_workers"
echo "Unhealthy workers: $((total_workers - healthy_workers))"

if [ "$overall_health" = "healthy" ]; then
    echo -e "${GREEN}✅ Overall Status: HEALTHY${NC}"
else
    echo -e "${RED}❌ Overall Status: UNHEALTHY${NC}"
    echo ""
    echo -e "${YELLOW}🔧 Troubleshooting:${NC}"
    echo "  • Check network connectivity and security groups"
    echo "  • Verify SSH key permissions"
    echo "  • Check GPU driver installation"
    echo "  • Restart Docker services if needed"
    echo "  • Deploy idle monitoring: ./step-323-gpu-worker-deploy-idle-monitor.sh"
fi

echo ""
echo -e "${BLUE}🎯 Next Steps:${NC}"
echo "  • View detailed status: ./step-321-gpu-worker-status.sh"
echo "  • Manage workers interactively: ./step-325-gpu-worker-manage-interactive.sh"
echo "  • Test transcription: ./step-330-fast-api-test-transcription.sh"

echo ""
echo -e "${BLUE}=======================================${NC}"

# Mark as completed and show next step
if [ "$overall_health" = "healthy" ]; then
    create_checkpoint "$SCRIPT_NAME" "completed" "$SCRIPT_NAME" 2>/dev/null || true
    log_info "GPU Worker Health Check completed - All workers healthy" "$SCRIPT_NAME" 2>/dev/null || echo "✅ GPU Worker Health Check completed - All workers healthy"
    
    # Show next step
    if declare -f show_next_step > /dev/null; then
        show_next_step "$(basename "$0")" "$(dirname "$0")"
    else
        echo -e "${BLUE}Next: Interactive management with step-325-gpu-worker-manage-interactive.sh${NC}"
    fi
else
    create_checkpoint "$SCRIPT_NAME" "failed" "$SCRIPT_NAME" 2>/dev/null || true
    log_error "GPU Worker Health Check failed - Some workers are unhealthy" "$SCRIPT_NAME" 2>/dev/null || echo "❌ GPU Worker Health Check failed - Some workers are unhealthy"
    exit 1
fi