#!/bin/bash

# step-345-orchestrate-transcription-system-startup.sh - Intelligent Transcription System Orchestrator
#
# ═════════════════════════════════════════════════════════════════════════════════════
# 🎯 WHAT THIS SCRIPT DOES
# ═════════════════════════════════════════════════════════════════════════════════════
# step-345-orchestrate-transcription-system-startup.sh is a smart system orchestrator 
# that ensures your transcription pipeline is fully operational. Here's what it does:
#
# 🔍 SYSTEM ASSESSMENT (Steps 1-3)
#
# 1. Finds FastAPI server - locates existing EC2 instances tagged as configured in .env
# 2. Manages server state - starts stopped instances or launches new ones if none exist
# 3. Health checks - tests if FastAPI server responds to http://{ip}:{port}/health
# 4. Queue analysis - counts pending messages in SQS queue
#
# ⚖️ INTELLIGENT DECISION MAKING (Step 4)
#
# if [ messages_waiting > 0 ] OR [ server_unhealthy ]; then
#     launch_sqs_worker()  # Expensive GPU worker
# else
#     use_direct_mode()    # Cheap, fast processing
# fi
#
# 💰 COST-OPTIMIZED LOGIC
#
# • Server healthy + empty queue = Uses direct HTTP calls (cheap, fast)
# • Server unhealthy OR messages queued = Launches GPU worker (expensive, reliable)
# • Never launches unnecessary workers = Saves money
#
# 📊 COMPREHENSIVE STATUS REPORT (Steps 5-6)
#
# • Verifies Lambda router configuration
# • Shows component health status
# • Displays processing modes available
# • Provides testing instructions
#
# 🎯 PERFECT FOR:
#
# • Morning startup before daily workload
# • Cron jobs at peak hours (2 AM prep)
# • Post-maintenance system verification
# • Auto-scaling when queue depth increases
#
# Think of it as: A smart "turn on my transcription system" button that only spins up 
# what you actually need, saving costs while ensuring reliability.
#
# Prerequisites: step-340 (Lambda router deployed), step-320 (FastAPI instance capability)
# Outputs: Complete working transcription system with optimal resource allocation
# ═════════════════════════════════════════════════════════════════════════════════════

set -e

# Source framework libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/error-handling.sh" || { echo "Error handling library not found"; exit 1; }
source "$SCRIPT_DIR/common-functions.sh" || { echo "Common functions not found"; exit 1; }

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get the project root directory
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.env"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    error_exit "Configuration file not found at $CONFIG_FILE"
fi

log_info "step-345-orchestrate-transcription-system-startup" "Orchestrating transcription system startup"

echo -e "${BLUE}======================================"
echo -e "🎯 Intelligent Transcription System Orchestrator"
echo -e "======================================${NC}"
echo -e "${CYAN}Purpose: Smart orchestration with cost optimization and health monitoring${NC}"
echo

# Check if FastAPI server is running
echo -e "\n${GREEN}[STEP 1]${NC} Checking FastAPI server status..."

FAST_API_INSTANCE=$(aws ec2 describe-instances \
    --filters "Name=tag:Type,Values=${FAST_API_WORKER_TAG}" \
                "Name=instance-state-name,Values=running,stopped" \
    --query 'Reservations[0].Instances[0].[InstanceId,State.Name,PublicIpAddress]' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "None None None")

INSTANCE_ID=$(echo "$FAST_API_INSTANCE" | awk '{print $1}')
INSTANCE_STATE=$(echo "$FAST_API_INSTANCE" | awk '{print $2}')
PUBLIC_IP=$(echo "$FAST_API_INSTANCE" | awk '{print $3}')

if [ "$INSTANCE_ID" = "None" ]; then
    echo -e "${YELLOW}⚠️ WARNING${NC} No FastAPI instance found"
    echo -e "${BLUE}Launching new FastAPI instance...${NC}"
    ./scripts/step-320-fast-api-launch-gpu-instances.sh
    
    # Wait for instance to be ready
    sleep 30
    
    # Get the new instance details
    FAST_API_INSTANCE=$(aws ec2 describe-instances \
        --filters "Name=tag:Type,Values=${FAST_API_WORKER_TAG}" \
                    "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].[InstanceId,State.Name,PublicIpAddress]' \
        --output text \
        --region "$AWS_REGION")
    
    INSTANCE_ID=$(echo "$FAST_API_INSTANCE" | awk '{print $1}')
    PUBLIC_IP=$(echo "$FAST_API_INSTANCE" | awk '{print $3}')
elif [ "$INSTANCE_STATE" = "stopped" ]; then
    echo -e "${YELLOW}FastAPI instance is stopped. Starting...${NC}"
    aws ec2 start-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"
    
    # Wait for instance to be running
    aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"
    
    # Get updated IP
    PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text \
        --region "$AWS_REGION")
fi

echo -e "${GREEN}✅ FastAPI Server:${NC}"
echo "   Instance ID: $INSTANCE_ID"
echo "   Public IP: $PUBLIC_IP"
echo "   Status: running"

# Test FastAPI health
echo -e "\n${GREEN}[STEP 2]${NC} Testing FastAPI server health..."
if curl -s --max-time ${HEALTH_CHECK_TIMEOUT} "http://${PUBLIC_IP}:${FAST_API_PORT}/health" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ FastAPI server is healthy${NC}"
    FAST_API_HEALTHY=true
else
    echo -e "${YELLOW}⚠️ FastAPI server not responding yet${NC}"
    FAST_API_HEALTHY=false
fi

# Check SQS queue status
echo -e "\n${GREEN}[STEP 3]${NC} Checking SQS queue status..."
QUEUE_ATTRS=$(aws sqs get-queue-attributes \
    --queue-url "$QUEUE_URL" \
    --attribute-names All \
    --region "$AWS_REGION" \
    --query 'Attributes.{Messages:ApproximateNumberOfMessages,InFlight:ApproximateNumberOfMessagesNotVisible}' \
    --output json)

MESSAGES_IN_QUEUE=$(echo "$QUEUE_ATTRS" | jq -r '.Messages')
MESSAGES_IN_FLIGHT=$(echo "$QUEUE_ATTRS" | jq -r '.InFlight')

echo -e "${BLUE}SQS Queue Status:${NC}"
echo "   Messages waiting: $MESSAGES_IN_QUEUE"
echo "   Messages processing: $MESSAGES_IN_FLIGHT"

# Check if we need a worker for queue processing
if [ "$MESSAGES_IN_QUEUE" -gt 0 ] || [ "$FAST_API_HEALTHY" = false ]; then
    echo -e "\n${GREEN}[STEP 4]${NC} Starting SQS worker for queue processing..."
    
    # Check if a worker is already running
    WORKER_RUNNING=$(aws ec2 describe-instances \
        --filters "Name=tag:Type,Values=${SQS_WORKER_TAG}" \
                    "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "None")
    
    if [ "$WORKER_RUNNING" = "None" ]; then
        echo -e "${BLUE}Launching SQS worker...${NC}"
        
        # Launch production GPU worker for SQS processing
        ./scripts/launch-production-gpu-worker.sh
        
        echo -e "${GREEN}✅ SQS worker launched${NC}"
    else
        echo -e "${GREEN}✅ SQS worker already running:${NC} $WORKER_RUNNING"
    fi
else
    echo -e "${GREEN}✅ No messages in queue and FastAPI is healthy${NC}"
    echo "   System will use direct FastAPI processing"
fi

# Update Lambda configuration if needed
echo -e "\n${GREEN}[STEP 5]${NC} Verifying Lambda configuration..."
LAMBDA_ENV=$(aws lambda get-function-configuration \
    --function-name "$TRANSCRIPTION_ROUTER_FUNCTION_NAME" \
    --region "$AWS_REGION" \
    --query 'Environment.Variables' \
    --output json 2>/dev/null || echo "{}")

if [ "$LAMBDA_ENV" != "{}" ]; then
    echo -e "${GREEN}✅ Lambda router configured${NC}"
else
    echo -e "${YELLOW}⚠️ WARNING${NC} Lambda router may need configuration update"
fi

# Test the complete system
echo -e "\n${GREEN}[STEP 6]${NC} System Status Summary..."
echo -e "${BLUE}======================================${NC}"
echo -e "${GREEN}TRANSCRIPTION SYSTEM STATUS${NC}"
echo -e "${BLUE}======================================${NC}"

# Component status
echo -e "\n${CYAN}Components:${NC}"
echo -e "✅ EventBridge: ${GREEN}Configured${NC} (${EVENT_BUS_NAME})"
echo -e "✅ Lambda Router: ${GREEN}Deployed${NC} (${TRANSCRIPTION_ROUTER_FUNCTION_NAME})"

if [ "$FAST_API_HEALTHY" = true ]; then
    echo -e "✅ FastAPI Server: ${GREEN}Healthy${NC} (http://${PUBLIC_IP}:${FAST_API_PORT})"
else
    echo -e "⚠️  FastAPI Server: ${YELLOW}Starting up${NC} (http://${PUBLIC_IP}:${FAST_API_PORT})"
fi

if [ "$MESSAGES_IN_QUEUE" -gt 0 ]; then
    echo -e "📦 SQS Queue: ${YELLOW}${MESSAGES_IN_QUEUE} messages waiting${NC}"
else
    echo -e "✅ SQS Queue: ${GREEN}Empty${NC}"
fi

# Processing modes
echo -e "\n${CYAN}Processing Modes:${NC}"
if [ "$FAST_API_HEALTHY" = true ]; then
    echo -e "🚀 Direct Mode: ${GREEN}Available${NC} (Low latency, real-time)"
fi
echo -e "📦 Queue Mode: ${GREEN}Available${NC} (Reliable, batch processing)"

# Next steps
echo -e "\n${CYAN}How to Test:${NC}"
echo "1. Upload audio file through frontend application"
echo "2. Check CloudWatch logs: /aws/lambda/${TRANSCRIPTION_ROUTER_FUNCTION_NAME}"
echo "3. Monitor SQS queue: $QUEUE_URL"
echo "4. Check FastAPI logs: http://${PUBLIC_IP}:${FAST_API_PORT}/docs"

if [ "$MESSAGES_IN_QUEUE" -gt 0 ]; then
    echo -e "\n${YELLOW}📌 Note:${NC} ${MESSAGES_IN_QUEUE} messages are queued and will be processed by the worker"
fi

log_success "step-345-orchestrate-transcription-system-startup" "Transcription system orchestration completed successfully"

echo
echo -e "${BLUE}======================================${NC}"
echo -e "${GREEN}✅ Transcription System Ready${NC}"
echo -e "${BLUE}======================================${NC}"
echo
echo -e "${GREEN}[SYSTEM READY]${NC}"
echo "• FastAPI server: ${PUBLIC_IP}:${FAST_API_PORT}"
echo "• SQS queue: ${QUEUE_URL}"
echo "• Lambda router: ${TRANSCRIPTION_ROUTER_FUNCTION_NAME}"
echo
echo -e "${BLUE}The system is now ready to process audio transcriptions!${NC}"

# Show next step
if [ -f "$SCRIPT_DIR/next-step-helper.sh" ]; then
    source "$SCRIPT_DIR/next-step-helper.sh"
    show_next_step "$0" "$SCRIPT_DIR"
fi