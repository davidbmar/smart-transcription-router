#!/bin/bash

# step-344-fix-system-permissions.sh - Fix all permission issues for transcription system

set -e

# Load common functions and error handling
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/error-handling.sh"
source "$SCRIPT_DIR/common-functions.sh"

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

log_info "step-344-fix-system-permissions" "Error handling initialized for step-344-fix-system-permissions"

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}🔧 Fix System Permissions${NC}"
echo -e "${BLUE}======================================${NC}"
echo -e "${CYAN}Purpose: Fix Lambda S3 permissions and SQS access${NC}"

LAMBDA_ROLE_NAME="${TRANSCRIPTION_ROUTER_FUNCTION_NAME}-role"

echo -e "\n${GREEN}[STEP 1]${NC} Fixing Lambda permissions..."
log_info "step-344-fix-system-permissions" "Updating Lambda role permissions"

# Get current account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create comprehensive policy for Lambda function
cat > /tmp/lambda-policy-complete.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "CloudWatchLogs",
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:${AWS_REGION}:*:*"
        },
        {
            "Sid": "SQSAccess",
            "Effect": "Allow",
            "Action": [
                "sqs:SendMessage",
                "sqs:GetQueueAttributes",
                "sqs:GetQueueUrl"
            ],
            "Resource": [
                "arn:aws:sqs:${AWS_REGION}:${ACCOUNT_ID}:*-queue",
                "arn:aws:sqs:${AWS_REGION}:${ACCOUNT_ID}:*-dlq"
            ]
        },
        {
            "Sid": "EC2Access",
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances"
            ],
            "Resource": "*"
        },
        {
            "Sid": "S3AudioAccess",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:GetObjectVersion",
                "s3:HeadObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::dbm-cf-2-web/*",
                "arn:aws:s3:::dbm-cf-2-web",
                "arn:aws:s3:::*-audio-*/*",
                "arn:aws:s3:::*-audio-*"
            ]
        }
    ]
}
EOF

# Update the Lambda role policy
aws iam put-role-policy \
    --role-name "$LAMBDA_ROLE_NAME" \
    --policy-name "${TRANSCRIPTION_ROUTER_FUNCTION_NAME}-policy" \
    --policy-document file:///tmp/lambda-policy-complete.json \
    --region "$AWS_REGION"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ SUCCESS${NC} Lambda permissions updated"
    log_success "step-344-fix-system-permissions" "Lambda role policy updated successfully"
else
    error_exit "Failed to update Lambda permissions"
fi

echo -e "\n${GREEN}[STEP 2]${NC} Checking SQS queue access..."

# Test SQS access
QUEUE_URL="https://sqs.${AWS_REGION}.amazonaws.com/${ACCOUNT_ID}/dbm-aud-ts-dev-aug92025-queue"
echo -e "${BLUE}Testing queue:${NC} $QUEUE_URL"

aws sqs get-queue-attributes \
    --queue-url "$QUEUE_URL" \
    --attribute-names QueueArn \
    --region "$AWS_REGION" \
    --output table

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ SUCCESS${NC} SQS queue is accessible"
else
    echo -e "${YELLOW}⚠️ WARNING${NC} SQS queue access issues"
fi

echo -e "\n${GREEN}[STEP 3]${NC} Checking FastAPI server S3 access..."

# The FastAPI server should use its EC2 instance profile to access S3
# Let's verify the instance has the right role attached
INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=*fast-api*" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null)

if [ "$INSTANCE_ID" != "None" ] && [ -n "$INSTANCE_ID" ]; then
    echo -e "${BLUE}FastAPI Instance:${NC} $INSTANCE_ID"
    
    INSTANCE_PROFILE=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null)
    
    if [ "$INSTANCE_PROFILE" != "None" ] && [ -n "$INSTANCE_PROFILE" ]; then
        echo -e "${GREEN}✅ Instance has IAM profile:${NC} $INSTANCE_PROFILE"
    else
        echo -e "${RED}❌ ERROR${NC} FastAPI instance missing IAM instance profile"
        echo -e "${BLUE}To fix manually:${NC}"
        echo "1. Create instance profile with S3 permissions"
        echo "2. Attach to EC2 instance $INSTANCE_ID"
    fi
else
    echo -e "${YELLOW}⚠️ WARNING${NC} No running FastAPI instance found"
fi

echo -e "\n${GREEN}[STEP 4]${NC} Testing end-to-end functionality..."

# Create a more realistic test event
cat > /tmp/test-realistic-event.json << EOF
{
  "Records": [
    {
      "eventSource": "aws:events",
      "eventName": "PutEvent", 
      "eventVersion": "1.0",
      "eventTime": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
      "awsRegion": "$AWS_REGION",
      "source": "custom.upload-service",
      "detail-type": "Audio Uploaded",
      "detail": {
        "userId": "test-user-123",
        "fileId": "test-audio-file",
        "s3Location": {
          "bucket": "dbm-cf-2-web",
          "key": "users/test-user/audio/sessions/20250809/chunk001.wav"
        },
        "metadata": {
          "contentType": "audio/wav",
          "size": 1048576,
          "format": "wav"
        },
        "userEmail": "test@example.com"
      }
    }
  ]
}
EOF

echo -e "${BLUE}Testing Lambda with realistic audio event...${NC}"
LAMBDA_RESULT=$(aws lambda invoke \
    --function-name "$TRANSCRIPTION_ROUTER_FUNCTION_NAME" \
    --payload file:///tmp/test-realistic-event.json \
    --region "$AWS_REGION" \
    /tmp/lambda-test-response.json 2>&1)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ SUCCESS${NC} Lambda invocation completed"
    echo -e "${BLUE}Response:${NC}"
    cat /tmp/lambda-test-response.json | python3 -m json.tool 2>/dev/null || cat /tmp/lambda-test-response.json
else
    echo -e "${YELLOW}⚠️ WARNING${NC} Lambda invocation had issues"
    echo "$LAMBDA_RESULT"
fi

# Cleanup temp files
rm -f /tmp/lambda-policy-complete.json /tmp/test-realistic-event.json /tmp/lambda-test-response.json

# Permissions fix completed

echo
echo -e "${BLUE}======================================${NC}"
echo -e "${GREEN}✅ System Permissions Fixed${NC}"
echo -e "${BLUE}======================================${NC}"
echo
echo -e "${GREEN}[PERMISSIONS UPDATED]${NC}"
echo "• Lambda can read S3 audio files (HeadObject, GetObject)"
echo "• Lambda can send messages to SQS queue"  
echo "• Lambda has CloudWatch logging permissions"
echo "• FastAPI server uses EC2 instance profile for S3 access"
echo
echo -e "${GREEN}[WHAT THIS FIXES]${NC}"
echo "• 403 Forbidden errors when accessing S3 objects"
echo "• SQS SendMessage permission denied errors"
echo "• End-to-end audio transcription flow"
echo
echo -e "${BLUE}[READY FOR TESTING]${NC}"
echo "1. Upload audio file in frontend application"
echo "2. EventBridge will trigger Lambda router"  
echo "3. Lambda will route to healthy FastAPI server"
echo "4. FastAPI server processes audio and returns transcription"

# Show next step
if [ -f "$SCRIPT_DIR/next-step-helper.sh" ]; then
    source "$SCRIPT_DIR/next-step-helper.sh"
    show_next_step "$0" "$SCRIPT_DIR"
fi