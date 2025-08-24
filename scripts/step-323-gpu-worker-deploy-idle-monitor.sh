#!/bin/bash
# step-323-gpu-worker-deploy-idle-monitor.sh - Deploy idle monitoring (30min auto-shutdown)
# Purpose: Deploy idle monitoring to all running GPU workers to prevent cost overruns

# Source navigation and error handling functions
source "$(dirname "$0")/step-navigation.sh" 2>/dev/null || {
    echo "Warning: Navigation functions not found"
}

source "$(dirname "$0")/error-handling.sh" 2>/dev/null || {
    echo "Warning: Error handling functions not found"
    set -e
}

# Initialize error handling
SCRIPT_NAME="step-323-gpu-worker-deploy-idle-monitor"
setup_error_handling "$SCRIPT_NAME" 2>/dev/null || true

log_info "Starting Idle Monitor Deployment" "$SCRIPT_NAME" 2>/dev/null || echo "⏰ Starting Idle Monitor Deployment"

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
echo -e "${BLUE}⏰ Deploy GPU Worker Idle Monitoring${NC}"
echo -e "${BLUE}=======================================${NC}"

REGION=${AWS_REGION:-us-east-2}
IDLE_TIMEOUT=${GPU_WORKER_IDLE_TIMEOUT_MINUTES:-30}
KEY_PATH=${KEY_PATH:-~/.ssh/transcription-worker.pem}
SCRIPT_DIR="$(dirname "$0")"

# Check if idle monitor script exists
IDLE_MONITOR_SCRIPT="/home/ubuntu/event-b/scripts/idle-monitor-gpu-worker.sh"
if [ ! -f "$IDLE_MONITOR_SCRIPT" ]; then
    echo -e "${RED}❌ Idle monitor script not found at: $IDLE_MONITOR_SCRIPT${NC}"
    echo "Expected location: /home/ubuntu/event-b/scripts/idle-monitor-gpu-worker.sh"
    exit 1
fi

echo -e "${CYAN}📋 Configuration:${NC}"
echo "  • Idle timeout: $IDLE_TIMEOUT minutes"
echo "  • SSH key: $KEY_PATH"
echo "  • AWS region: $REGION"
echo "  • Metrics bucket: ${METRICS_BUCKET:-not configured}"
echo ""

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
    echo "  ./step-320-fast-api-launch-gpu-instances.sh  (launch new)"
    echo "  ./step-322-gpu-worker-start-stopped.sh       (start existing)"
    echo ""
    exit 1
fi

# Display found instances
echo ""
echo -e "${GREEN}📋 Found running GPU workers:${NC}"
echo "┌────────────────────────┬─────────────────┬──────────────┬─────────────────┐"
echo "│ Name                   │ Instance ID     │ Public IP    │ Type            │"
echo "├────────────────────────┼─────────────────┼──────────────┼─────────────────┤"

echo "$INSTANCE_INFO" | jq -r '.[][] | @tsv' | while IFS=$'\t' read -r instance_id public_ip instance_type instance_name; do
    [ "$public_ip" = "null" ] && public_ip="(no IP)"
    [ "$instance_name" = "null" ] && instance_name="unnamed"
    [ -z "$instance_name" ] && instance_name="unnamed"
    
    if [ ${#instance_name} -gt 22 ]; then
        instance_name="${instance_name:0:19}..."
    fi
    
    printf "│ %-22s │ %-15s │ %-12s │ %-15s │\n" \
        "$instance_name" "$instance_id" "$public_ip" "$instance_type"
done

echo "└────────────────────────┴─────────────────┴──────────────┴─────────────────┘"

echo ""
echo -e "${YELLOW}⚠️  This will deploy auto-shutdown to ALL running workers${NC}"
echo "Workers will automatically shut down after $IDLE_TIMEOUT minutes of idle time"
echo ""
read -p "Continue with deployment? (y/N): " confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled"
    exit 0
fi

# Check SSH key exists
if [ ! -f "$KEY_PATH" ]; then
    echo -e "${RED}❌ SSH key not found: $KEY_PATH${NC}"
    echo "Update KEY_PATH in .env or ensure key exists"
    exit 1
fi

# Deploy to each instance
echo ""
echo -e "${BLUE}🚀 Deploying idle monitoring to all workers...${NC}"
echo ""

deployment_count=0
success_count=0
failed_instances=()

echo "$INSTANCE_INFO" | jq -r '.[][] | @tsv' | while IFS=$'\t' read -r instance_id public_ip instance_type instance_name; do
    if [ "$public_ip" = "null" ] || [ -z "$public_ip" ]; then
        echo -e "${YELLOW}⏭️  Skipping $instance_name ($instance_id) - no public IP${NC}"
        continue
    fi
    
    deployment_count=$((deployment_count + 1))
    echo -e "${CYAN}📦 Deploying to: $instance_name ($instance_id)${NC}"
    echo "  Instance Type: $instance_type"
    echo "  Public IP: $public_ip"
    echo "  Idle Timeout: $IDLE_TIMEOUT minutes"
    
    # Test SSH connectivity first
    echo -n "  Testing SSH connection... "
    if timeout 10 ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
        ubuntu@$public_ip 'echo "connected"' >/dev/null 2>&1; then
        echo -e "${GREEN}✅${NC}"
    else
        echo -e "${RED}❌ SSH failed${NC}"
        failed_instances+=("$instance_name ($instance_id)")
        continue
    fi
    
    # Copy the idle monitor script to the instance
    echo -n "  Copying idle monitor script... "
    if scp -i "$KEY_PATH" -o StrictHostKeyChecking=no \
        "$IDLE_MONITOR_SCRIPT" ubuntu@$public_ip:/tmp/idle-monitor-gpu-worker.sh >/dev/null 2>&1; then
        echo -e "${GREEN}✅${NC}"
    else
        echo -e "${RED}❌ Copy failed${NC}"
        failed_instances+=("$instance_name ($instance_id)")
        continue
    fi
    
    # Deploy and start the idle monitor
    echo -n "  Setting up systemd service... "
    if ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no ubuntu@$public_ip << EOF >/dev/null 2>&1
        # Make script executable
        chmod +x /tmp/idle-monitor-gpu-worker.sh
        sudo mv /tmp/idle-monitor-gpu-worker.sh /usr/local/bin/idle-monitor-gpu-worker.sh
        
        # Stop any existing idle monitor
        sudo pkill -f idle-monitor-gpu-worker || true
        sudo systemctl stop gpu-idle-monitor 2>/dev/null || true
        
        # Create systemd service for idle monitor
        sudo tee /etc/systemd/system/gpu-idle-monitor.service > /dev/null << 'SERVICE'
[Unit]
Description=GPU Worker Idle Monitor
After=network.target

[Service]
Type=simple
User=root
Environment="IDLE_TIMEOUT_MINUTES=$IDLE_TIMEOUT"
Environment="METRICS_BUCKET=${METRICS_BUCKET:-}"
ExecStart=/usr/local/bin/idle-monitor-gpu-worker.sh
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
SERVICE
        
        # Reload systemd and start the service
        sudo systemctl daemon-reload
        sudo systemctl enable gpu-idle-monitor.service
        sudo systemctl start gpu-idle-monitor.service
        
        # Verify it started
        sleep 2
        sudo systemctl is-active gpu-idle-monitor.service >/dev/null
EOF
    then
        echo -e "${GREEN}✅${NC}"
        success_count=$((success_count + 1))
    else
        echo -e "${RED}❌ Service setup failed${NC}"
        failed_instances+=("$instance_name ($instance_id)")
        continue
    fi
    
    echo -e "${GREEN}  ✅ Successfully deployed to $instance_name${NC}"
    echo ""
done

# Summary
echo -e "${BLUE}=======================================${NC}"
echo -e "${BLUE}📊 Deployment Summary${NC}"
echo -e "${BLUE}=======================================${NC}"
echo ""
echo "Deployment attempts: $deployment_count"
echo "Successful deployments: $success_count"
echo "Failed deployments: $((${#failed_instances[@]}))"

if [ ${#failed_instances[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}❌ Failed instances:${NC}"
    for instance in "${failed_instances[@]}"; do
        echo "  • $instance"
    done
fi

if [ $success_count -gt 0 ]; then
    echo ""
    echo -e "${GREEN}✅ Idle monitoring deployed successfully!${NC}"
    echo ""
    echo -e "${CYAN}📋 Monitoring Details:${NC}"
    echo "  • Idle timeout: $IDLE_TIMEOUT minutes"
    echo "  • Workers will auto-shutdown after idle period"
    echo "  • Only GPU worker instances will shutdown (not dev instance)"
    echo "  • Logs will be uploaded to S3 before shutdown"
    echo ""
    echo -e "${CYAN}🔍 To monitor idle status:${NC}"
    echo "  ssh -i $KEY_PATH ubuntu@<worker-ip> 'sudo journalctl -u gpu-idle-monitor -f'"
    echo ""
    echo -e "${CYAN}🛑 To disable auto-shutdown on a worker:${NC}"
    echo "  ssh -i $KEY_PATH ubuntu@<worker-ip> 'sudo systemctl stop gpu-idle-monitor'"
    echo ""
    echo -e "${CYAN}📊 View worker status:${NC}"
    echo "  ./step-321-gpu-worker-status.sh"
else
    echo ""
    echo -e "${RED}❌ No successful deployments${NC}"
    echo "Check network connectivity and SSH key permissions"
fi

echo ""
echo -e "${BLUE}=======================================${NC}"

# Mark as completed and show next step
create_checkpoint "$SCRIPT_NAME" "completed" "$SCRIPT_NAME" 2>/dev/null || true
log_info "Idle Monitor Deployment completed" "$SCRIPT_NAME" 2>/dev/null || echo "✅ Idle Monitor Deployment completed"

# Show next step
if declare -f show_next_step > /dev/null; then
    show_next_step "$(basename "$0")" "$(dirname "$0")"
else
    echo -e "${BLUE}Next: Check worker health with step-324-gpu-worker-health-check.sh${NC}"
fi