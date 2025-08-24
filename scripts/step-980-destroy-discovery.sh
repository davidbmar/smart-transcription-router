#!/bin/bash
# step-980-destroy-discovery.sh - Discover all resources from .env files

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}=======================================${NC}"
echo -e "${BLUE}🔍 Resource Discovery for Destruction${NC}"
echo -e "${BLUE}=======================================${NC}"

# Output file
OUTPUT_FILE="/tmp/resources-to-destroy.json"
DISCOVERY_LOG="/tmp/discovery.log"

echo -e "${CYAN}📋 Discovering resources from .env files...${NC}"
echo ""

# Initialize JSON structure
cat > "$OUTPUT_FILE" << 'EOF'
{
  "discovery_timestamp": "",
  "env_files_scanned": [],
  "instances": [],
  "lambda_functions": [],
  "sqs_queues": [],
  "eventbridge_resources": [],
  "s3_buckets": [],
  "iam_resources": [],
  "ecr_repositories": [],
  "security_groups": [],
  "key_pairs": [],
  "other_resources": []
}
EOF

# Update timestamp
jq --arg ts "$(date -u '+%Y-%m-%d %H:%M:%S UTC')" '.discovery_timestamp = $ts' "$OUTPUT_FILE" > /tmp/temp.json && mv /tmp/temp.json "$OUTPUT_FILE"

# Function to add discovered resource
add_resource() {
    local category="$1"
    local resource_type="$2" 
    local resource_id="$3"
    local resource_name="$4"
    local source_file="$5"
    
    jq --arg cat "$category" \
       --arg type "$resource_type" \
       --arg id "$resource_id" \
       --arg name "$resource_name" \
       --arg src "$source_file" \
       '.[$cat] += [{"type": $type, "id": $id, "name": $name, "source": $src}]' \
       "$OUTPUT_FILE" > /tmp/temp.json && mv /tmp/temp.json "$OUTPUT_FILE"
}

# Function to scan .env file
scan_env_file() {
    local env_file="$1"\n    local project_dir="$2"\n    \n    echo -e "${YELLOW}📁 Scanning: $env_file${NC}"\n    \n    if [ ! -f "$env_file" ]; then\n        echo "  ⏭️  File not found, skipping"\n        return\n    fi\n    \n    # Add to scanned files list\n    jq --arg file "$env_file" '.env_files_scanned += [$file]' "$OUTPUT_FILE" > /tmp/temp.json && mv /tmp/temp.json "$OUTPUT_FILE"\n    \n    # Source the file to get variables\n    set +e  # Don't exit on errors in .env files\n    source "$env_file"\n    set -e\n    \n    local resources_found=0\n    \n    # EC2 Instances (look for various instance ID patterns)\n    for var_name in WORKER_INSTANCE_ID FAST_API_INSTANCE_ID GPU_WORKER_INSTANCE_ID INSTANCE_ID; do\n        local instance_id=$(grep "^export $var_name=" "$env_file" 2>/dev/null | cut -d'\"' -f2 || echo "")\n        if [[ "$instance_id" =~ ^i-[0-9a-f]{8,17}$ ]]; then\n            echo "  🖥️  Instance: $instance_id ($var_name)"\n            add_resource "instances" "EC2Instance" "$instance_id" "$var_name" "$env_file"\n            resources_found=$((resources_found + 1))\n        fi\n    done\n    \n    # Lambda Functions\n    for var_name in TRANSCRIPTION_ROUTER_FUNCTION_NAME LAMBDA_FUNCTION_NAME FAST_API_FUNCTION_NAME; do\n        local function_name=$(grep "^export $var_name=" "$env_file" 2>/dev/null | cut -d'\"' -f2 || echo "")\n        if [ -n "$function_name" ] && [ "$function_name" != "your-function-name" ]; then\n            echo "  λ  Lambda: $function_name ($var_name)"\n            add_resource "lambda_functions" "LambdaFunction" "$function_name" "$var_name" "$env_file"\n            resources_found=$((resources_found + 1))\n        fi\n    done\n    \n    # SQS Queues\n    for var_name in QUEUE_URL DLQ_URL QUEUE_NAME DLQ_NAME; do\n        local queue_value=$(grep "^export $var_name=" "$env_file" 2>/dev/null | cut -d'\"' -f2 || echo "")\n        if [[ "$queue_value" =~ sqs.*amazonaws\.com ]] || [[ "$queue_value" =~ ^[a-zA-Z0-9_-]+$ ]]; then\n            echo "  📬 Queue: $queue_value ($var_name)"\n            add_resource "sqs_queues" "SQSQueue" "$queue_value" "$var_name" "$env_file"\n            resources_found=$((resources_found + 1))\n        fi\n    done\n    \n    # EventBridge Resources\n    for var_name in EVENT_BUS_NAME EVENT_RULE_NAME; do\n        local event_resource=$(grep "^export $var_name=" "$env_file" 2>/dev/null | cut -d'\"' -f2 || echo "")\n        if [ -n "$event_resource" ] && [ "$event_resource" != "your-event-bus" ]; then\n            echo "  🚌 EventBridge: $event_resource ($var_name)"\n            add_resource "eventbridge_resources" "EventBridge" "$event_resource" "$var_name" "$env_file"\n            resources_found=$((resources_found + 1))\n        fi\n    done\n    \n    # S3 Buckets\n    for var_name in AUDIO_BUCKET METRICS_BUCKET S3_BUCKET_NAME; do\n        local bucket_name=$(grep "^export $var_name=" "$env_file" 2>/dev/null | cut -d'\"' -f2 || echo "")\n        if [ -n "$bucket_name" ] && [ "$bucket_name" != "your-bucket-name" ]; then\n            echo "  🪣 S3 Bucket: $bucket_name ($var_name)"\n            add_resource "s3_buckets" "S3Bucket" "$bucket_name" "$var_name" "$env_file"\n            resources_found=$((resources_found + 1))\n        fi\n    done\n    \n    # IAM Resources\n    for var_name in WORKER_ROLE_NAME WORKER_INSTANCE_PROFILE IAM_ROLE_ARN; do\n        local iam_resource=$(grep "^export $var_name=" "$env_file" 2>/dev/null | cut -d'\"' -f2 || echo "")\n        if [ -n "$iam_resource" ] && [[ ! "$iam_resource" =~ ^(your-|arn:aws:iam::123456789012:).*$ ]]; then\n            echo "  🔐 IAM: $iam_resource ($var_name)"\n            add_resource "iam_resources" "IAM" "$iam_resource" "$var_name" "$env_file"\n            resources_found=$((resources_found + 1))\n        fi\n    done\n    \n    # ECR Repositories\n    for var_name in FAST_API_ECR_REPO_NAME RNNT_ECR_REPO_NAME ECR_REPOSITORY_URI; do\n        local ecr_resource=$(grep "^export $var_name=" "$env_file" 2>/dev/null | cut -d'\"' -f2 || echo "")\n        if [ -n "$ecr_resource" ] && [[ ! "$ecr_resource" =~ ^(your-|123456789012).*$ ]]; then\n            echo "  🐳 ECR: $ecr_resource ($var_name)"\n            add_resource "ecr_repositories" "ECRRepository" "$ecr_resource" "$var_name" "$env_file"\n            resources_found=$((resources_found + 1))\n        fi\n    done\n    \n    # Security Groups\n    for var_name in SECURITY_GROUP_ID; do\n        local sg_id=$(grep "^export $var_name=" "$env_file" 2>/dev/null | cut -d'\"' -f2 || echo "")\n        if [[ "$sg_id" =~ ^sg-[0-9a-f]{8,17}$ ]]; then\n            echo "  🛡️  Security Group: $sg_id ($var_name)"\n            add_resource "security_groups" "SecurityGroup" "$sg_id" "$var_name" "$env_file"\n            resources_found=$((resources_found + 1))\n        fi\n    done\n    \n    # Key Pairs\n    for var_name in KEY_NAME INSTANCE_KEY_NAME; do\n        local key_name=$(grep "^export $var_name=" "$env_file" 2>/dev/null | cut -d'\"' -f2 || echo "")\n        if [ -n "$key_name" ] && [ "$key_name" != "your-key-name" ]; then\n            echo "  🔑 Key Pair: $key_name ($var_name)"\n            add_resource "key_pairs" "KeyPair" "$key_name" "$var_name" "$env_file"\n            resources_found=$((resources_found + 1))\n        fi\n    done\n    \n    echo "  📊 Found $resources_found resources in this file"\n    echo ""\n}\n\n# Scan all .env files in the project\necho -e "${CYAN}🔍 Scanning for .env files in project...${NC}"\necho ""\n\n# Find all .env files\nfind /home/ubuntu/event-b -name \".env\" -type f 2>/dev/null | while read -r env_file; do\n    project_dir=$(dirname "$env_file")\n    scan_env_file "$env_file" "$project_dir"\ndone\n\n# Generate summary\necho -e "${BLUE}📊 Discovery Summary${NC}"\necho "======================================="\n\n# Count resources by category\ninstances_count=$(jq '.instances | length' "$OUTPUT_FILE")\nlambdas_count=$(jq '.lambda_functions | length' "$OUTPUT_FILE")\nqueues_count=$(jq '.sqs_queues | length' "$OUTPUT_FILE")\neventbridge_count=$(jq '.eventbridge_resources | length' "$OUTPUT_FILE")\ns3_count=$(jq '.s3_buckets | length' "$OUTPUT_FILE")\niam_count=$(jq '.iam_resources | length' "$OUTPUT_FILE")\necr_count=$(jq '.ecr_repositories | length' "$OUTPUT_FILE")\nsg_count=$(jq '.security_groups | length' "$OUTPUT_FILE")\nkey_count=$(jq '.key_pairs | length' "$OUTPUT_FILE")\n\ntotal_resources=$((instances_count + lambdas_count + queues_count + eventbridge_count + s3_count + iam_count + ecr_count + sg_count + key_count))\n\necho "EC2 Instances: $instances_count"\necho "Lambda Functions: $lambdas_count"\necho "SQS Queues: $queues_count"\necho "EventBridge Resources: $eventbridge_count"\necho "S3 Buckets: $s3_count"\necho "IAM Resources: $iam_count"\necho "ECR Repositories: $ecr_count"\necho "Security Groups: $sg_count"\necho "Key Pairs: $key_count"\necho ""\necho -e "${CYAN}Total Resources Discovered: $total_resources${NC}"\n\n# Save detailed discovery info\necho ""\necho -e "${GREEN}✅ Discovery complete!${NC}"\necho "Results saved to: $OUTPUT_FILE"\necho ""\necho -e "${YELLOW}📋 Next Steps:${NC}"\necho "1. Run ./step-990-destroy-validation.sh to check which resources exist in AWS"\necho "2. Run ./step-999-destroy-execute-all.sh to destroy everything"\necho ""\necho -e "${CYAN}📄 View discovery results:${NC}"\necho "cat $OUTPUT_FILE | jq ."\necho ""\necho -e "${BLUE}=======================================${NC}"\n\n# Show quick preview\nif [ "$total_resources" -gt 0 ]; then\n    echo -e "${CYAN}🔍 Quick Preview of Discovered Resources:${NC}"\n    echo ""\n    \n    if [ "$instances_count" -gt 0 ]; then\n        echo "EC2 Instances:"\n        jq -r '.instances[] | "  • " + .id + " (" + .name + ")"' "$OUTPUT_FILE"\n        echo ""\n    fi\n    \n    if [ "$s3_count" -gt 0 ]; then\n        echo "S3 Buckets:"\n        jq -r '.s3_buckets[] | "  • " + .id + " (" + .name + ")"' "$OUTPUT_FILE"\n        echo ""\n    fi\n    \n    if [ "$lambdas_count" -gt 0 ]; then\n        echo "Lambda Functions:"\n        jq -r '.lambda_functions[] | "  • " + .id + " (" + .name + ")"' "$OUTPUT_FILE"\n        echo ""\n    fi\nfi

# Mark as completed and show next step
create_checkpoint "$SCRIPT_NAME" "completed" "$SCRIPT_NAME" 2>/dev/null || true
log_info "Resource Discovery completed" "$SCRIPT_NAME" 2>/dev/null || echo "✅ Resource Discovery completed"

# Show next step
if declare -f show_next_step > /dev/null; then
    show_next_step "$(basename "$0")" "$(dirname "$0")"
else
    echo -e "${BLUE}Next: Validate resources with step-990-destroy-validation.sh${NC}"
fi
