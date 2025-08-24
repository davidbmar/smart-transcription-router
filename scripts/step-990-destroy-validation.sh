#!/bin/bash
# step-990-destroy-validation.sh - Check which resources actually exist in AWS

set -e

# Source configuration
if [ -f ".env" ]; then
    source .env
else
    echo "⚠️  .env file not found - using defaults"
fi

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}=======================================${NC}"
echo -e "${BLUE}✅ Resource Validation & Destruction Planning${NC}"
echo -e "${BLUE}=======================================${NC}"

REGION=${AWS_REGION:-us-east-2}
DISCOVERY_FILE="/tmp/resources-to-destroy.json"
VALIDATION_OUTPUT="/tmp/destruction-plan.json"

# Check if discovery file exists
if [ ! -f "$DISCOVERY_FILE" ]; then
    echo -e "${RED}❌ Discovery file not found: $DISCOVERY_FILE${NC}"
    echo "Run ./step-980-destroy-discovery.sh first"
    exit 1
fi

echo -e "${CYAN}📋 Validating discovered resources against AWS...${NC}"
echo "Region: $REGION"
echo ""

# Initialize validation output
cat > "$VALIDATION_OUTPUT" << 'EOF'
{
  "validation_timestamp": "",
  "region": "",
  "existing_resources": {
    "instances": [],
    "lambda_functions": [],
    "sqs_queues": [],
    "eventbridge_resources": [],
    "s3_buckets": [],
    "iam_resources": [],
    "ecr_repositories": [],
    "security_groups": [],
    "key_pairs": []
  },
  "missing_resources": [],
  "cost_analysis": {
    "estimated_hourly_cost": 0,
    "estimated_daily_cost": 0,
    "estimated_monthly_cost": 0
  },
  "destruction_order": [],
  "warnings": []
}
EOF

# Update metadata
jq --arg ts "$(date -u '+%Y-%m-%d %H:%M:%S UTC')" \
   --arg region "$REGION" \
   '.validation_timestamp = $ts | .region = $region' \
   "$VALIDATION_OUTPUT" > /tmp/temp.json && mv /tmp/temp.json "$VALIDATION_OUTPUT"

# Function to add existing resource
add_existing_resource() {
    local category="$1"
    local resource="$2"
    local cost="${3:-0}"
    
    jq --arg cat "$category" \
       --argjson res "$resource" \
       --arg cost "$cost" \
       '.existing_resources[$cat] += [$res] | 
        .cost_analysis.estimated_hourly_cost += ($cost | tonumber)' \
       "$VALIDATION_OUTPUT" > /tmp/temp.json && mv /tmp/temp.json "$VALIDATION_OUTPUT"
}

# Function to add missing resource
add_missing_resource() {
    local resource_type="$1"
    local resource_id="$2"
    local reason="$3"
    
    jq --arg type "$resource_type" \
       --arg id "$resource_id" \
       --arg reason "$reason" \
       '.missing_resources += [{"type": $type, "id": $id, "reason": $reason}]' \
       "$VALIDATION_OUTPUT" > /tmp/temp.json && mv /tmp/temp.json "$VALIDATION_OUTPUT"
}

# Function to add warning
add_warning() {
    local message="$1"
    
    jq --arg msg "$message" \
       '.warnings += [$msg]' \
       "$VALIDATION_OUTPUT" > /tmp/temp.json && mv /tmp/temp.json "$VALIDATION_OUTPUT"
}

# Validate EC2 Instances
echo -e "${YELLOW}🖥️  Validating EC2 instances...${NC}"
instance_ids=$(jq -r '.instances[] | .id' "$DISCOVERY_FILE" 2>/dev/null || echo "")

if [ -n "$instance_ids" ]; then
    for instance_id in $instance_ids; do
        echo -n "  Checking $instance_id... "
        
        instance_info=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --region "$REGION" \
            --query 'Reservations[0].Instances[0].[InstanceId,State.Name,InstanceType,LaunchTime,Tags[?Key==`Name`].Value | [0]]' \
            --output json 2>/dev/null || echo "null")
        
        if [ "$instance_info" != "null" ] && [ "$instance_info" != "[]" ]; then
            state=$(echo "$instance_info" | jq -r '.[1]')
            instance_type=$(echo "$instance_info" | jq -r '.[2]')
            launch_time=$(echo "$instance_info" | jq -r '.[3]')
            name=$(echo "$instance_info" | jq -r '.[4]' | sed 's/null/unnamed/')
            
            # Calculate cost
            case "$instance_type" in
                "g4dn.xlarge") hourly_cost=0.526 ;;
                "g4dn.2xlarge") hourly_cost=0.752 ;;
                "g5.xlarge") hourly_cost=1.006 ;;
                "p3.2xlarge") hourly_cost=3.06 ;;
                "t3.micro") hourly_cost=0.0104 ;;
                "t3.small") hourly_cost=0.0208 ;;
                *) hourly_cost=0.10 ;;
            esac
            
            # Only count cost if running
            if [ "$state" = "running" ]; then
                cost_impact=$hourly_cost
                echo -e "${RED}EXISTS (RUNNING - \\$$hourly_cost/hr)${NC}"
            else
                cost_impact=0
                echo -e "${YELLOW}EXISTS ($state - \\$0/hr)${NC}"
            fi
            
            resource_json=$(cat << EOF
{
  "id": "$instance_id",
  "state": "$state",
  "type": "$instance_type",
  "name": "$name",
  "launch_time": "$launch_time",
  "hourly_cost": $hourly_cost,
  "cost_impact": $cost_impact
}
EOF
            )\n            \n            add_existing_resource "instances" "$resource_json" "$cost_impact"\n            \n            if [ "$state" = "running" ]; then\n                add_warning "Instance $instance_id ($name) is running and incurring costs"\n            fi\n        else\n            echo -e "${GREEN}NOT FOUND${NC}"\n            add_missing_resource "EC2Instance" "$instance_id" "Instance does not exist or access denied"\n        fi\n    done\nelse\n    echo "  No instances found in discovery"\nfi\n\necho ""\n\n# Validate Lambda Functions\necho -e "${YELLOW}λ  Validating Lambda functions...${NC}"\nfunction_names=$(jq -r '.lambda_functions[] | .id' "$DISCOVERY_FILE" 2>/dev/null || echo "")\n\nif [ -n "$function_names" ]; then\n    for function_name in $function_names; do\n        echo -n "  Checking $function_name... "\n        \n        function_info=$(aws lambda get-function \\\n            --function-name "$function_name" \\\n            --region "$REGION" \\\n            --query '[Configuration.FunctionName,Configuration.Runtime,Configuration.CodeSize,Configuration.LastModified]' \\\n            --output json 2>/dev/null || echo "null")\n        \n        if [ "$function_info" != "null" ]; then\n            runtime=$(echo "$function_info" | jq -r '.[1]')\n            code_size=$(echo "$function_info" | jq -r '.[2]')\n            last_modified=$(echo "$function_info" | jq -r '.[3]')\n            \n            echo -e "${RED}EXISTS${NC}"\n            \n            resource_json=$(cat << EOF\n{\n  "name": "$function_name",\n  "runtime": "$runtime",\n  "code_size": $code_size,\n  "last_modified": "$last_modified"\n}\nEOF\n            )\n            \n            add_existing_resource "lambda_functions" "$resource_json" "0"\n        else\n            echo -e "${GREEN}NOT FOUND${NC}"\n            add_missing_resource "LambdaFunction" "$function_name" "Function does not exist or access denied"\n        fi\n    done\nelse\n    echo "  No Lambda functions found in discovery"\nfi\n\necho ""\n\n# Validate S3 Buckets\necho -e "${YELLOW}🪣 Validating S3 buckets...${NC}"\nbucket_names=$(jq -r '.s3_buckets[] | .id' "$DISCOVERY_FILE" 2>/dev/null || echo "")\n\nif [ -n "$bucket_names" ]; then\n    for bucket_name in $bucket_names; do\n        echo -n "  Checking $bucket_name... "\n        \n        bucket_info=$(aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null && echo "exists" || echo "not_found")\n        \n        if [ "$bucket_info" = "exists" ]; then\n            # Check if bucket has contents\n            object_count=$(aws s3 ls "s3://$bucket_name" --recursive --summarize | grep "Total Objects:" | awk '{print $3}' || echo "0")\n            total_size=$(aws s3 ls "s3://$bucket_name" --recursive --summarize | grep "Total Size:" | awk '{print $3}' || echo "0")\n            \n            echo -e "${RED}EXISTS ($object_count objects, $total_size bytes)${NC}"\n            \n            resource_json=$(cat << EOF\n{\n  "name": "$bucket_name",\n  "object_count": "$object_count",\n  "total_size": "$total_size"\n}\nEOF\n            )\n            \n            add_existing_resource "s3_buckets" "$resource_json" "0"\n            \n            if [ "$object_count" -gt 0 ]; then\n                add_warning "S3 bucket $bucket_name contains $object_count objects - deletion will destroy data"\n            fi\n        else\n            echo -e "${GREEN}NOT FOUND${NC}"\n            add_missing_resource "S3Bucket" "$bucket_name" "Bucket does not exist or access denied"\n        fi\n    done\nelse\n    echo "  No S3 buckets found in discovery"\nfi\n\necho ""\n\n# Validate SQS Queues\necho -e "${YELLOW}📬 Validating SQS queues...${NC}"\nqueue_identifiers=$(jq -r '.sqs_queues[] | .id' "$DISCOVERY_FILE" 2>/dev/null || echo "")\n\nif [ -n "$queue_identifiers" ]; then\n    for queue_id in $queue_identifiers; do\n        echo -n "  Checking $queue_id... "\n        \n        # Try as URL first, then as name\n        if [[ "$queue_id" =~ https://sqs ]]; then\n            queue_url="$queue_id"\n        else\n            queue_url=$(aws sqs get-queue-url --queue-name "$queue_id" --region "$REGION" --query 'QueueUrl' --output text 2>/dev/null || echo "not_found")\n        fi\n        \n        if [ "$queue_url" != "not_found" ] && [ -n "$queue_url" ]; then\n            # Get queue attributes\n            approx_messages=$(aws sqs get-queue-attributes \\\n                --queue-url "$queue_url" \\\n                --attribute-names ApproximateNumberOfMessages \\\n                --region "$REGION" \\\n                --query 'Attributes.ApproximateNumberOfMessages' \\\n                --output text 2>/dev/null || echo "0")\n            \n            echo -e "${RED}EXISTS ($approx_messages messages)${NC}"\n            \n            resource_json=$(cat << EOF\n{\n  "url": "$queue_url",\n  "approximate_messages": "$approx_messages"\n}\nEOF\n            )\n            \n            add_existing_resource "sqs_queues" "$resource_json" "0"\n        else\n            echo -e "${GREEN}NOT FOUND${NC}"\n            add_missing_resource "SQSQueue" "$queue_id" "Queue does not exist or access denied"\n        fi\n    done\nelse\n    echo "  No SQS queues found in discovery"\nfi\n\n# Calculate final costs\njq '.cost_analysis.estimated_daily_cost = (.cost_analysis.estimated_hourly_cost * 24) | \n   .cost_analysis.estimated_monthly_cost = (.cost_analysis.estimated_hourly_cost * 24 * 30)' \\\n   "$VALIDATION_OUTPUT" > /tmp/temp.json && mv /tmp/temp.json "$VALIDATION_OUTPUT"\n\n# Generate destruction order\necho -e "${CYAN}📋 Generating destruction order...${NC}"\n\n# Define safe destruction order\nDESTRUCTION_ORDER='[\n  {"category": "instances", "description": "Stop/terminate EC2 instances first"},\n  {"category": "lambda_functions", "description": "Delete Lambda functions"},\n  {"category": "eventbridge_resources", "description": "Delete EventBridge rules"},\n  {"category": "sqs_queues", "description": "Delete SQS queues"},\n  {"category": "s3_buckets", "description": "Delete S3 buckets (WARNING: data loss)"},\n  {"category": "ecr_repositories", "description": "Delete ECR repositories"},\n  {"category": "iam_resources", "description": "Delete IAM resources last"},\n  {"category": "security_groups", "description": "Delete security groups"},\n  {"category": "key_pairs", "description": "Delete key pairs"}\n]'\n\njq --argjson order "$DESTRUCTION_ORDER" '.destruction_order = $order' \\\n   "$VALIDATION_OUTPUT" > /tmp/temp.json && mv /tmp/temp.json "$VALIDATION_OUTPUT"\n\n# Summary\necho ""\necho -e "${BLUE}=======================================${NC}"\necho -e "${BLUE}📊 Validation Summary${NC}"\necho -e "${BLUE}=======================================${NC}"\n\nexisting_instances=$(jq '.existing_resources.instances | length' "$VALIDATION_OUTPUT")\nexisting_lambdas=$(jq '.existing_resources.lambda_functions | length' "$VALIDATION_OUTPUT")\nexisting_buckets=$(jq '.existing_resources.s3_buckets | length' "$VALIDATION_OUTPUT")\nexisting_queues=$(jq '.existing_resources.sqs_queues | length' "$VALIDATION_OUTPUT")\nmissing_count=$(jq '.missing_resources | length' "$VALIDATION_OUTPUT")\nwarning_count=$(jq '.warnings | length' "$VALIDATION_OUTPUT")\nhourly_cost=$(jq '.cost_analysis.estimated_hourly_cost' "$VALIDATION_OUTPUT")\ndaily_cost=$(jq '.cost_analysis.estimated_daily_cost' "$VALIDATION_OUTPUT")\nmonthly_cost=$(jq '.cost_analysis.estimated_monthly_cost' "$VALIDATION_OUTPUT")\n\necho -e "${CYAN}Resources Found in AWS:${NC}"\necho "  EC2 Instances: $existing_instances"\necho "  Lambda Functions: $existing_lambdas"\necho "  S3 Buckets: $existing_buckets"\necho "  SQS Queues: $existing_queues"\necho "  Missing/Inaccessible: $missing_count"\necho ""\necho -e "${CYAN}Cost Analysis:${NC}"\nprintf "  Current hourly cost: \\$%.2f\\n" "$hourly_cost"\nprintf "  Estimated daily cost: \\$%.2f\\n" "$daily_cost"\nprintf "  Estimated monthly cost: \\$%.2f\\n" "$monthly_cost"\n\nif [ "$warning_count" -gt 0 ]; then\n    echo ""\n    echo -e "${YELLOW}⚠️  Warnings ($warning_count):${NC}"\n    jq -r '.warnings[]' "$VALIDATION_OUTPUT" | sed 's/^/  • /'\nfi\n\necho ""\necho -e "${GREEN}✅ Validation complete!${NC}"\necho "Destruction plan saved to: $VALIDATION_OUTPUT"\necho ""\necho -e "${YELLOW}📋 Next Steps:${NC}"\nif [ "$((existing_instances + existing_lambdas + existing_buckets + existing_queues))" -gt 0 ]; then\n    echo "1. Review the destruction plan: cat $VALIDATION_OUTPUT | jq ."\n    echo "2. Execute destruction: ./step-999-destroy-execute-all.sh"\n    echo ""\n    echo -e "${RED}⚠️  WARNING: Destruction will permanently delete resources and data!${NC}"\nelse\n    echo "1. No existing resources found - nothing to destroy"\n    echo "2. You may want to clean up .env files manually"\nfi\n\necho ""\necho -e "${BLUE}=======================================${NC}"

# Mark as completed and show next step
create_checkpoint "$SCRIPT_NAME" "completed" "$SCRIPT_NAME" 2>/dev/null || true
log_info "Resource Validation completed" "$SCRIPT_NAME" 2>/dev/null || echo "✅ Resource Validation completed"

# Show next step
if declare -f show_next_step > /dev/null; then
    show_next_step "$(basename "$0")" "$(dirname "$0")"
else
    echo -e "${BLUE}Next: Execute destruction with step-999-destroy-execute-all.sh${NC}"
fi
