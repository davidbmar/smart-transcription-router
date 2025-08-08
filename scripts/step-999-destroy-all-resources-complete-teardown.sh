#!/bin/bash

# step-999-destroy-all-resources-complete-teardown.sh - Destroy all resources and configuration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Display script information
echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║         COMPLETE SYSTEM TEARDOWN - DESTROY ALL                ║${NC}"
echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${RED}⚠️  WARNING: This script performs a COMPLETE TEARDOWN! ⚠️${NC}"
echo
echo -e "${BLUE}ℹ️  SCOPE: This script only destroys resources created by smart-transcription-router${NC}"
echo -e "${BLUE}   It will NOT affect resources created by other projects (eventbridge-orchestrator, etc.)${NC}"
echo

# Initial confirmation
read -p "Do you want to proceed with COMPLETE TEARDOWN? (yes/no): " INITIAL_CONFIRM

if [ "$INITIAL_CONFIRM" != "yes" ]; then
    echo -e "${GREEN}[INFO]${NC} Teardown cancelled. No resources were affected."
    exit 0
fi

# Function to print colored output
print_header() {
    echo ""
    echo -e "${RED}=== $1 ===${NC}"
    echo ""
}

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_danger() {
    echo -e "${RED}[DANGER]${NC} $1"
}

# Check if configuration exists and load it
if [ ! -f ".env" ]; then
    echo -e "${RED}[ERROR]${NC} No configuration file found. Nothing to destroy."
    exit 1
fi

# Load configuration early so variables are available for display
source .env

# Now show the detailed overview with actual values
echo -e "${YELLOW}This script will PERMANENTLY DELETE:${NC}"
echo
echo -e "${RED}AWS Resources (created by smart-transcription-router only):${NC}"
echo "  • FastAPI worker EC2 instances (tag: fast-api-worker)"
echo "  • Legacy whisper worker instances (tag: whisper-worker)"  
echo "  • SQS queues: ${QUEUE_NAME:-[not configured]} and ${DLQ_NAME:-[not configured]}"
echo "  • S3 metrics bucket: ${METRICS_BUCKET:-[not configured]}"
echo "  • ECR repository: ${FAST_API_ECR_REPO_NAME:-[not configured]} (and all images)"
echo "  • Lambda function: ${TRANSCRIPTION_ROUTER_FUNCTION_NAME:-[not configured]}"
echo "  • EventBridge rules that target this project's Lambda"
echo "  • IAM roles and policies specific to this project"
echo
echo -e "${RED}Local Files:${NC}"
echo "  • Configuration files (.env backups, status files)"
echo "  • Generated credentials and setup tracking files"
echo
echo -e "${GREEN}What will be PRESERVED (created by other projects):${NC}"
echo "  • Audio bucket: ${AUDIO_BUCKET:-[not configured]} (shared storage - NOT deleted)"
echo "  • EventBridge bus: ${EVENT_BUS_NAME:-[not configured]} (created by eventbridge-orchestrator)"
echo "  • Any resources not specifically created by smart-transcription-router"
echo "  • Your source code and git repository"
echo
echo -e "${YELLOW}When to use this script:${NC}"
echo "  • Starting completely fresh from scratch"
echo "  • Cleaning up after testing/development"
echo "  • Removing all traces of the system"
echo
echo -e "${YELLOW}Alternative:${NC} Use step-999-terminate-workers-or-selective-cleanup.sh"
echo "for selective cleanup that preserves infrastructure."
echo

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}🔍 DISCOVERY: Scanning AWS for resources${NC}"
echo -e "${BLUE}======================================${NC}"

# Discover what actually exists in AWS based on .env configuration
print_status "Discovering resources based on .env configuration..."

echo -e "${CYAN}FastAPI EC2 Instances:${NC}"
FASTAPI_INSTANCES=$(aws ec2 describe-instances \
    --filters "Name=tag:Type,Values=fast-api-worker" \
              "Name=instance-state-name,Values=running,pending,stopping,stopped" \
    --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress]' \
    --output table \
    --region "$AWS_REGION" 2>/dev/null || echo "None found")
echo "$FASTAPI_INSTANCES"

echo -e "${CYAN}SQS Queues:${NC}"
if aws sqs get-queue-attributes --queue-url "$QUEUE_URL" &>/dev/null; then
    echo "  ✓ Main queue: $QUEUE_NAME"
else
    echo "  ✗ Main queue: $QUEUE_NAME (not found)"
fi
if aws sqs get-queue-attributes --queue-url "$DLQ_URL" &>/dev/null; then
    echo "  ✓ DLQ: $DLQ_NAME"
else
    echo "  ✗ DLQ: $DLQ_NAME (not found)"
fi

echo -e "${CYAN}S3 Buckets:${NC}"
if aws s3 ls "s3://$METRICS_BUCKET" &>/dev/null; then
    echo "  ✓ Metrics bucket: $METRICS_BUCKET"
else
    echo "  ✗ Metrics bucket: $METRICS_BUCKET (not found)"
fi
echo "  → Audio bucket: $AUDIO_BUCKET (will be preserved)"

echo -e "${CYAN}ECR Repository:${NC}"
if aws ecr describe-repositories --repository-names "$FAST_API_ECR_REPO_NAME" --region "$AWS_REGION" &>/dev/null; then
    IMAGE_COUNT=$(aws ecr list-images --repository-name "$FAST_API_ECR_REPO_NAME" --region "$AWS_REGION" --query 'length(imageIds)' --output text 2>/dev/null || echo "0")
    echo "  ✓ Repository: $FAST_API_ECR_REPO_NAME ($IMAGE_COUNT images)"
else
    echo "  ✗ Repository: $FAST_API_ECR_REPO_NAME (not found)"
fi

echo -e "${CYAN}Lambda Function:${NC}"
if aws lambda get-function --function-name "$TRANSCRIPTION_ROUTER_FUNCTION_NAME" --region "$AWS_REGION" &>/dev/null; then
    echo "  ✓ Function: $TRANSCRIPTION_ROUTER_FUNCTION_NAME"
else
    echo "  ✗ Function: $TRANSCRIPTION_ROUTER_FUNCTION_NAME (not found)"
fi

echo -e "${CYAN}EventBridge Rules:${NC}"
AUDIO_RULE="${QUEUE_PREFIX}-audio-upload-rule"
BATCH_RULE="${QUEUE_PREFIX}-midnight-batch-rule"
if aws events describe-rule --name "$AUDIO_RULE" --event-bus-name "$EVENT_BUS_NAME" --region "$AWS_REGION" &>/dev/null; then
    echo "  ✓ Audio upload rule: $AUDIO_RULE"
else
    echo "  ✗ Audio upload rule: $AUDIO_RULE (not found)"
fi
if aws events describe-rule --name "$BATCH_RULE" --region "$AWS_REGION" &>/dev/null; then
    echo "  ✓ Batch processing rule: $BATCH_RULE"
else
    echo "  ✗ Batch processing rule: $BATCH_RULE (not found)"
fi
echo "  → EventBridge bus: $EVENT_BUS_NAME (will be preserved - created by eventbridge-orchestrator)"

echo
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}📋 DESTRUCTION MAP: What will be deleted${NC}"
echo -e "${BLUE}======================================${NC}"

# Build destruction map based on discovery
RESOURCES_TO_DELETE=()
RESOURCES_COUNT=0

# Check FastAPI instances
FASTAPI_FOUND=$(aws ec2 describe-instances \
    --filters "Name=tag:Type,Values=fast-api-worker" \
              "Name=instance-state-name,Values=running,pending,stopping,stopped" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")
if [ -n "$FASTAPI_FOUND" ] && [ "$FASTAPI_FOUND" != "None" ]; then
    RESOURCES_TO_DELETE+=("FastAPI EC2 instances: $(echo $FASTAPI_FOUND | wc -w) instances")
    RESOURCES_COUNT=$((RESOURCES_COUNT + 1))
fi

# Check whisper instances  
WHISPER_FOUND=$(aws ec2 describe-instances \
    --filters "Name=tag:Type,Values=whisper-worker" \
              "Name=instance-state-name,Values=running,pending,stopping,stopped" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")
if [ -n "$WHISPER_FOUND" ] && [ "$WHISPER_FOUND" != "None" ]; then
    RESOURCES_TO_DELETE+=("Whisper EC2 instances: $(echo $WHISPER_FOUND | wc -w) instances")
    RESOURCES_COUNT=$((RESOURCES_COUNT + 1))
fi

# Check SQS queues
if aws sqs get-queue-attributes --queue-url "$QUEUE_URL" &>/dev/null; then
    RESOURCES_TO_DELETE+=("SQS Main Queue: $QUEUE_NAME")
    RESOURCES_COUNT=$((RESOURCES_COUNT + 1))
fi
if aws sqs get-queue-attributes --queue-url "$DLQ_URL" &>/dev/null; then
    RESOURCES_TO_DELETE+=("SQS Dead Letter Queue: $DLQ_NAME")
    RESOURCES_COUNT=$((RESOURCES_COUNT + 1))
fi

# Check S3 metrics bucket
if aws s3 ls "s3://$METRICS_BUCKET" &>/dev/null; then
    RESOURCES_TO_DELETE+=("S3 Metrics Bucket: $METRICS_BUCKET")
    RESOURCES_COUNT=$((RESOURCES_COUNT + 1))
fi

# Check ECR repository
if aws ecr describe-repositories --repository-names "$FAST_API_ECR_REPO_NAME" --region "$AWS_REGION" &>/dev/null; then
    IMAGE_COUNT=$(aws ecr list-images --repository-name "$FAST_API_ECR_REPO_NAME" --region "$AWS_REGION" --query 'length(imageIds)' --output text 2>/dev/null || echo "0")
    RESOURCES_TO_DELETE+=("ECR Repository: $FAST_API_ECR_REPO_NAME ($IMAGE_COUNT images)")
    RESOURCES_COUNT=$((RESOURCES_COUNT + 1))
fi

# Check Lambda function
if aws lambda get-function --function-name "$TRANSCRIPTION_ROUTER_FUNCTION_NAME" --region "$AWS_REGION" &>/dev/null; then
    RESOURCES_TO_DELETE+=("Lambda Function: $TRANSCRIPTION_ROUTER_FUNCTION_NAME")
    RESOURCES_COUNT=$((RESOURCES_COUNT + 1))
fi

# Check EventBridge rules
if aws events describe-rule --name "$AUDIO_RULE" --event-bus-name "$EVENT_BUS_NAME" --region "$AWS_REGION" &>/dev/null; then
    RESOURCES_TO_DELETE+=("EventBridge Rule: $AUDIO_RULE")
    RESOURCES_COUNT=$((RESOURCES_COUNT + 1))
fi
if aws events describe-rule --name "$BATCH_RULE" --region "$AWS_REGION" &>/dev/null; then
    RESOURCES_TO_DELETE+=("EventBridge Rule: $BATCH_RULE")
    RESOURCES_COUNT=$((RESOURCES_COUNT + 1))
fi

# Check IAM resources
if aws iam get-role --role-name "${QUEUE_PREFIX}-transcription-router-role" &>/dev/null; then
    RESOURCES_TO_DELETE+=("IAM Lambda Role: ${QUEUE_PREFIX}-transcription-router-role")
    RESOURCES_COUNT=$((RESOURCES_COUNT + 1))
fi
if aws iam get-role --role-name "transcription-worker-role" &>/dev/null; then
    RESOURCES_TO_DELETE+=("IAM Worker Role: transcription-worker-role")
    RESOURCES_COUNT=$((RESOURCES_COUNT + 1))
fi
if aws iam get-instance-profile --instance-profile-name "$WORKER_INSTANCE_PROFILE" &>/dev/null; then
    RESOURCES_TO_DELETE+=("IAM Instance Profile: $WORKER_INSTANCE_PROFILE")
    RESOURCES_COUNT=$((RESOURCES_COUNT + 1))
fi

# Show destruction map
if [ $RESOURCES_COUNT -eq 0 ]; then
    echo -e "${GREEN}✅ NO RESOURCES FOUND TO DELETE${NC}"
    echo "All resources from smart-transcription-router have already been cleaned up."
    echo "Nothing to destroy!"
    exit 0
else
    echo -e "${RED}🗑️  FOUND $RESOURCES_COUNT RESOURCES TO DELETE:${NC}"
    for resource in "${RESOURCES_TO_DELETE[@]}"; do
        echo -e "  ${RED}✗${NC} $resource"
    done
fi

echo
echo -e "${GREEN}🔒 RESOURCES THAT WILL BE PRESERVED:${NC}"
echo -e "  ${GREEN}✓${NC} Audio bucket: $AUDIO_BUCKET (shared storage)"
echo -e "  ${GREEN}✓${NC} EventBridge bus: $EVENT_BUS_NAME (created by eventbridge-orchestrator)"
echo -e "  ${GREEN}✓${NC} Your source code and git repository"

echo

echo -e "${RED}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                    DANGER: DESTROY ALL                        ║"
echo "║         This will permanently delete all resources!           ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

print_danger "Resources created by smart-transcription-router that will be DESTROYED:"
echo ""
echo -e "${RED}SQS Queues:${NC}"
echo "  - $QUEUE_NAME ($QUEUE_URL)"
echo "  - $DLQ_NAME ($DLQ_URL)"
echo ""
echo -e "${RED}S3 Buckets:${NC}"
echo -e "  - ${RED}$METRICS_BUCKET${NC} (will be DELETED - project-specific)"
echo ""
echo -e "${RED}ECR Repository:${NC}"
echo "  - $FAST_API_ECR_REPO_NAME (all images will be deleted)"
echo ""
echo -e "${RED}Lambda Functions:${NC}"
echo "  - $TRANSCRIPTION_ROUTER_FUNCTION_NAME"
echo ""
echo -e "${RED}EventBridge Rules (targeting our Lambda):${NC}"
echo "  - ${QUEUE_PREFIX}-audio-upload-rule"
echo "  - ${QUEUE_PREFIX}-midnight-batch-rule"
echo ""
echo -e "${RED}EC2 Resources:${NC}"
echo "  - All instances tagged as 'fast-api-worker'"
echo "  - All instances tagged as 'whisper-worker'"  
echo "  - All active spot instance requests"
echo ""
echo -e "${RED}IAM Resources (project-specific):${NC}"
echo "  - Policy: TranscriptionSystemUserPolicy"
echo "  - Policy: TranscriptionWorkerPolicy"
echo "  - Role: transcription-worker-role"
echo "  - Role: ${QUEUE_PREFIX}-transcription-router-role"
echo "  - Instance Profile: $WORKER_INSTANCE_PROFILE"
echo ""
echo -e "${GREEN}PRESERVED Resources (created by other projects):${NC}"
echo -e "  - ${GREEN}Audio bucket: $AUDIO_BUCKET${NC} (shared - NOT deleted)"
echo -e "  - ${GREEN}EventBridge bus: $EVENT_BUS_NAME${NC} (created by eventbridge-orchestrator - NOT deleted)"
echo ""
echo -e "${RED}Local Files:${NC}"
echo "  - .env backup files, status files, generated configs"
echo ""

# Confirmation
read -p "Are you ABSOLUTELY SURE you want to destroy all resources? Type 'DESTROY ALL' to confirm: " CONFIRM

if [ "$CONFIRM" != "DESTROY ALL" ]; then
    print_warning "Destruction cancelled."
    exit 0
fi

# Double confirmation
read -p "This is your LAST CHANCE. Type the environment name '$ENVIRONMENT' to confirm: " CONFIRM_ENV

if [ "$CONFIRM_ENV" != "$ENVIRONMENT" ]; then
    print_warning "Environment name mismatch. Destruction cancelled."
    exit 0
fi

print_header "Starting Resource Destruction"

# Step 1: Terminate EC2 instances
print_header "Terminating EC2 Instances"

# Find and terminate FastAPI worker instances
FASTAPI_INSTANCE_IDS=$(aws ec2 describe-instances \
    --filters "Name=tag:Type,Values=fast-api-worker" \
              "Name=instance-state-name,Values=running,pending,stopping,stopped" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

if [ -n "$FASTAPI_INSTANCE_IDS" ] && [ "$FASTAPI_INSTANCE_IDS" != "None" ]; then
    print_status "Terminating FastAPI instances: $FASTAPI_INSTANCE_IDS"
    aws ec2 terminate-instances \
        --instance-ids $FASTAPI_INSTANCE_IDS \
        --region "$AWS_REGION" || print_warning "Failed to terminate some FastAPI instances"
else
    print_status "No FastAPI worker instances found"
fi

# Find and terminate whisper worker instances (legacy)
WHISPER_INSTANCE_IDS=$(aws ec2 describe-instances \
    --filters "Name=tag:Type,Values=whisper-worker" \
              "Name=instance-state-name,Values=running,pending,stopping,stopped" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

if [ -n "$WHISPER_INSTANCE_IDS" ] && [ "$WHISPER_INSTANCE_IDS" != "None" ]; then
    print_status "Terminating whisper instances: $WHISPER_INSTANCE_IDS"
    aws ec2 terminate-instances \
        --instance-ids $WHISPER_INSTANCE_IDS \
        --region "$AWS_REGION" || print_warning "Failed to terminate some whisper instances"
else
    print_status "No whisper worker instances found"
fi

# Cancel spot instance requests
SPOT_REQUESTS=$(aws ec2 describe-spot-instance-requests \
    --filters "Name=state,Values=active,open" \
    --query 'SpotInstanceRequests[*].SpotInstanceRequestId' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

if [ -n "$SPOT_REQUESTS" ] && [ "$SPOT_REQUESTS" != "None" ]; then
    print_status "Cancelling spot requests: $SPOT_REQUESTS"
    aws ec2 cancel-spot-instance-requests \
        --spot-instance-request-ids $SPOT_REQUESTS \
        --region "$AWS_REGION" || print_warning "Failed to cancel some spot requests"
else
    print_status "No active spot requests found"
fi

# Step 2: Delete SQS queues
print_header "Deleting SQS Queues"

# Delete main queue
if [ -n "$QUEUE_URL" ]; then
    print_status "Deleting queue: $QUEUE_NAME"
    aws sqs delete-queue \
        --queue-url "$QUEUE_URL" \
        --region "$AWS_REGION" 2>/dev/null || print_warning "Queue may already be deleted"
fi

# Delete DLQ
if [ -n "$DLQ_URL" ]; then
    print_status "Deleting DLQ: $DLQ_NAME"
    aws sqs delete-queue \
        --queue-url "$DLQ_URL" \
        --region "$AWS_REGION" 2>/dev/null || print_warning "DLQ may already be deleted"
fi

# Step 3: Delete ECR Repository and Images
print_header "Deleting ECR Repository"

if [ -n "$FAST_API_ECR_REPO_NAME" ]; then
    print_status "Deleting ECR repository: $FAST_API_ECR_REPO_NAME"
    
    # List all images in the repository
    IMAGE_DIGESTS=$(aws ecr list-images \
        --repository-name "$FAST_API_ECR_REPO_NAME" \
        --query 'imageIds[*].imageDigest' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [ -n "$IMAGE_DIGESTS" ] && [ "$IMAGE_DIGESTS" != "None" ]; then
        print_status "Deleting all images from repository"
        # Delete all images (including both tagged and untagged)
        aws ecr list-images \
            --repository-name "$FAST_API_ECR_REPO_NAME" \
            --query 'imageIds[*]' \
            --output json \
            --region "$AWS_REGION" | \
        aws ecr batch-delete-image \
            --repository-name "$FAST_API_ECR_REPO_NAME" \
            --image-ids file:///dev/stdin \
            --region "$AWS_REGION" 2>/dev/null || print_warning "Failed to delete some images"
    fi
    
    # Delete the repository
    aws ecr delete-repository \
        --repository-name "$FAST_API_ECR_REPO_NAME" \
        --force \
        --region "$AWS_REGION" 2>/dev/null || print_warning "ECR repository may already be deleted"
else
    print_status "No ECR repository configured"
fi

# Step 4: Delete Lambda Functions and EventBridge Rules
print_header "Deleting Lambda Functions and EventBridge Rules"

# Delete EventBridge rules first (they target the Lambda)
if [ -n "$QUEUE_PREFIX" ] && [ -n "$EVENT_BUS_NAME" ]; then
    print_status "Deleting EventBridge rules"
    
    # Delete audio upload rule
    AUDIO_RULE_NAME="${QUEUE_PREFIX}-audio-upload-rule"
    aws events remove-targets \
        --rule "$AUDIO_RULE_NAME" \
        --event-bus-name "$EVENT_BUS_NAME" \
        --ids "1" \
        --region "$AWS_REGION" 2>/dev/null || print_warning "Failed to remove targets from audio rule"
    
    aws events delete-rule \
        --name "$AUDIO_RULE_NAME" \
        --event-bus-name "$EVENT_BUS_NAME" \
        --region "$AWS_REGION" 2>/dev/null || print_warning "Audio upload rule may already be deleted"
    
    # Delete midnight batch rule (may not have targets)
    BATCH_RULE_NAME="${QUEUE_PREFIX}-midnight-batch-rule"
    aws events delete-rule \
        --name "$BATCH_RULE_NAME" \
        --region "$AWS_REGION" 2>/dev/null || print_warning "Midnight batch rule may already be deleted"
else
    print_status "No EventBridge rules configured"
fi

# Delete Lambda function
if [ -n "$TRANSCRIPTION_ROUTER_FUNCTION_NAME" ]; then
    print_status "Deleting Lambda function: $TRANSCRIPTION_ROUTER_FUNCTION_NAME"
    aws lambda delete-function \
        --function-name "$TRANSCRIPTION_ROUTER_FUNCTION_NAME" \
        --region "$AWS_REGION" 2>/dev/null || print_warning "Lambda function may already be deleted"
else
    print_status "No Lambda function configured"
fi

# Step 5: Delete S3 buckets
print_header "Deleting S3 Buckets"

# Delete metrics bucket (must be empty first, including all versions)
if [ -n "$METRICS_BUCKET" ]; then
    if aws s3 ls "s3://$METRICS_BUCKET" 2>/dev/null; then
        print_status "Emptying bucket: $METRICS_BUCKET"
        
        # Delete all objects
        aws s3 rm "s3://$METRICS_BUCKET" --recursive || print_warning "Failed to empty bucket"
        
        # Check if versioning is enabled and delete all versions
        print_status "Checking for versioned objects in $METRICS_BUCKET"
        VERSIONS=$(aws s3api list-object-versions \
            --bucket "$METRICS_BUCKET" \
            --output json \
            --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}, DeleteMarkers: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
            2>/dev/null || echo "{}")
            
        if [ "$VERSIONS" != "{}" ] && [ -n "$VERSIONS" ]; then
            print_status "Deleting all object versions and delete markers"
            echo "$VERSIONS" | aws s3api delete-objects \
                --bucket "$METRICS_BUCKET" \
                --delete "$(echo "$VERSIONS" | jq -c '{Objects: (.Objects + .DeleteMarkers) | map(select(. != null))}')" \
                2>/dev/null || print_warning "Failed to delete some versions"
        fi
        
        # Now delete the bucket
        print_status "Deleting bucket: $METRICS_BUCKET"
        aws s3 rb "s3://$METRICS_BUCKET" --force || print_warning "Failed to delete bucket"
    else
        print_status "Bucket $METRICS_BUCKET not found or already deleted"
    fi
fi

# Step 6: Delete IAM resources
print_header "Deleting IAM Resources"

# Delete Lambda IAM role and policy
LAMBDA_ROLE_NAME="${QUEUE_PREFIX}-transcription-router-role"
LAMBDA_POLICY_NAME="${QUEUE_PREFIX}-transcription-router-policy"

if [ -n "$LAMBDA_ROLE_NAME" ]; then
    print_status "Deleting Lambda role policy: $LAMBDA_POLICY_NAME"
    aws iam delete-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-name "$LAMBDA_POLICY_NAME" \
        2>/dev/null || print_warning "Lambda policy already deleted"
    
    print_status "Deleting Lambda role: $LAMBDA_ROLE_NAME"
    aws iam delete-role \
        --role-name "$LAMBDA_ROLE_NAME" \
        2>/dev/null || print_warning "Lambda role already deleted"
fi

# Detach and delete policies for worker
print_status "Detaching policies from user $IAM_USER"
aws iam detach-user-policy \
    --user-name "$IAM_USER" \
    --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/TranscriptionSystemUserPolicy" \
    2>/dev/null || print_warning "Policy already detached from user"

print_status "Detaching policies from worker role"
aws iam detach-role-policy \
    --role-name "transcription-worker-role" \
    --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/TranscriptionWorkerPolicy" \
    2>/dev/null || print_warning "Policy already detached from role"

# Delete policies
print_status "Deleting user policy"
aws iam delete-policy \
    --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/TranscriptionSystemUserPolicy" \
    2>/dev/null || print_warning "User policy already deleted"

print_status "Deleting worker policy"
aws iam delete-policy \
    --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/TranscriptionWorkerPolicy" \
    2>/dev/null || print_warning "Worker policy already deleted"

# Remove role from instance profile and delete
if [ -n "$WORKER_INSTANCE_PROFILE" ]; then
    print_status "Cleaning up instance profile: $WORKER_INSTANCE_PROFILE"
    aws iam remove-role-from-instance-profile \
        --instance-profile-name "$WORKER_INSTANCE_PROFILE" \
        --role-name "transcription-worker-role" \
        2>/dev/null || print_warning "Role already removed from instance profile"

    aws iam delete-instance-profile \
        --instance-profile-name "$WORKER_INSTANCE_PROFILE" \
        2>/dev/null || print_warning "Instance profile already deleted"
fi

# Delete worker role
print_status "Deleting worker IAM role"
aws iam delete-role \
    --role-name "transcription-worker-role" \
    2>/dev/null || print_warning "Worker role already deleted"

# Step 7: Clean up local files
print_header "Cleaning Up Local Files"

print_status "Removing configuration files..."
rm -f .env.backup*
rm -f .setup-status
rm -f NEXT_STEPS.md
rm -f queue-resources-summary.txt
rm -f transcription-config.env
rm -f worker-config.env
rm -f docker.env
rm -f queue-config.env
rm -f iam-config.env

print_status "Configuration files removed"

# Final summary
print_header "Destruction Complete"

echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║              All resources have been destroyed!               ║"
echo "║         The transcription system has been removed.            ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

print_status "Summary of destroyed resources:"
echo "  - FastAPI and whisper worker EC2 instances terminated"
echo "  - Spot instance requests cancelled"
echo "  - SQS queues (main queue and DLQ) deleted"
echo "  - ECR repository and all Docker images deleted"
echo "  - Lambda function deleted"
echo "  - EventBridge rules and targets deleted"
echo "  - S3 metrics bucket deleted"
echo "  - IAM policies, roles, and instance profiles deleted"
echo "  - All configuration files removed"
echo ""
print_warning "Note: The audio bucket '${GREEN}$AUDIO_BUCKET${NC}' was ${GREEN}NOT deleted${NC} as it may contain important data."
print_warning "Note: The EventBridge bus '${GREEN}$EVENT_BUS_NAME${NC}' was ${GREEN}NOT deleted${NC} as it may be shared with other projects."
echo ""
print_status "To set up the system again, run: ./scripts/step-000-setup-configuration.sh"