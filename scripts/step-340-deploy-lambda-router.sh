#!/bin/bash

# step-340-deploy-lambda-router.sh - Deploy Lambda router for smart transcription routing

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load configuration
CONFIG_FILE=".env"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo -e "${RED}[ERROR]${NC} Configuration file not found."
    exit 1
fi

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}🚀 Deploy Lambda Transcription Router${NC}"
echo -e "${BLUE}======================================${NC}"
echo

# Verify prerequisites
if [ -z "$QUEUE_URL" ]; then
    echo -e "${RED}[ERROR]${NC} QUEUE_URL not found. Run step-020-create-sqs-resources.sh first."
    exit 1
fi

# Set SQS_QUEUE_URL for Lambda environment
SQS_QUEUE_URL="$QUEUE_URL"

echo -e "${GREEN}[STEP 1]${NC} Creating Lambda deployment package..."

# Create temp directory for deployment
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Copy Lambda code
cp /home/ubuntu/event-b/smart-transcription-router/lambdas/transcription-router/index.py .
cp /home/ubuntu/event-b/smart-transcription-router/lambdas/transcription-router/requirements.txt .

# Install dependencies
echo -e "${YELLOW}[INFO]${NC} Installing Python dependencies..."
pip install -r requirements.txt -t . --quiet

# Create deployment package
echo -e "${YELLOW}[INFO]${NC} Creating deployment package..."
zip -r lambda-deployment.zip . -q

echo -e "${GREEN}[STEP 2]${NC} Creating Lambda execution role..."

# Create trust policy
cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create the role
ROLE_NAME="${QUEUE_PREFIX}-transcription-router-role"
if ! aws iam get-role --role-name "$ROLE_NAME" 2>/dev/null; then
    echo -e "${YELLOW}[INFO]${NC} Creating IAM role: $ROLE_NAME"
    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document file://trust-policy.json \
        --description "Role for transcription router Lambda"
fi

# Wait for role to be available
sleep 5

# Create policy for Lambda
cat > lambda-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:${AWS_REGION}:*:*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "sqs:SendMessage",
                "sqs:GetQueueAttributes"
            ],
            "Resource": "arn:aws:sqs:${AWS_REGION}:*:${QUEUE_PREFIX}-*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:HeadObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${AUDIO_BUCKET}",
                "arn:aws:s3:::${AUDIO_BUCKET}/*"
            ]
        }
    ]
}
EOF

# Attach policy to role
POLICY_NAME="${QUEUE_PREFIX}-transcription-router-policy"
aws iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "$POLICY_NAME" \
    --policy-document file://lambda-policy.json

# Get role ARN
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)

echo -e "${GREEN}[STEP 3]${NC} Creating Lambda function..."

FUNCTION_NAME="${QUEUE_PREFIX}-transcription-router"

# Check if function exists
if aws lambda get-function --function-name "$FUNCTION_NAME" 2>/dev/null; then
    echo -e "${YELLOW}[INFO]${NC} Updating existing Lambda function..."
    aws lambda update-function-code \
        --function-name "$FUNCTION_NAME" \
        --zip-file fileb://lambda-deployment.zip \
        --region "$AWS_REGION"
    
    # Update function configuration
    aws lambda update-function-configuration \
        --function-name "$FUNCTION_NAME" \
        --timeout 30 \
        --memory-size 512 \
        --environment "Variables={SQS_QUEUE_URL=$SQS_QUEUE_URL,FAST_API_TAG=fast-api-worker}" \
        --region "$AWS_REGION"
else
    echo -e "${YELLOW}[INFO]${NC} Creating new Lambda function..."
    aws lambda create-function \
        --function-name "$FUNCTION_NAME" \
        --runtime python3.9 \
        --role "$ROLE_ARN" \
        --handler index.lambda_handler \
        --zip-file fileb://lambda-deployment.zip \
        --timeout 30 \
        --memory-size 512 \
        --environment "Variables={SQS_QUEUE_URL=$SQS_QUEUE_URL,FAST_API_TAG=fast-api-worker}" \
        --description "Routes transcription requests with exponential backoff retry to FastAPI or SQS" \
        --region "$AWS_REGION"
fi

# Get Lambda ARN
LAMBDA_ARN=$(aws lambda get-function --function-name "$FUNCTION_NAME" --query 'Configuration.FunctionArn' --output text)

# Save Lambda configuration
echo "TRANSCRIPTION_ROUTER_LAMBDA_ARN=$LAMBDA_ARN" >> "$CONFIG_FILE"
echo "TRANSCRIPTION_ROUTER_FUNCTION_NAME=$FUNCTION_NAME" >> "$CONFIG_FILE"

# Clean up
cd /
rm -rf "$TEMP_DIR"

echo
echo -e "${BLUE}======================================${NC}"
echo -e "${GREEN}✅ Lambda Router Deployed${NC}"
echo -e "${BLUE}======================================${NC}"
echo
echo -e "${GREEN}[LAMBDA DETAILS]${NC}"
echo "Function Name: $FUNCTION_NAME"
echo "Function ARN: $LAMBDA_ARN"
echo "Role: $ROLE_NAME"
echo
echo -e "${GREEN}[NEXT STEPS]${NC}"
echo "1. Configure EventBridge to trigger this Lambda:"
echo "   ./scripts/step-341-configure-eventbridge-trigger.sh"
echo
echo "2. Test the router:"
echo "   ./scripts/step-342-test-lambda-router.sh"
echo
echo -e "${YELLOW}[ROUTING LOGIC]${NC}"
echo "• Idempotent processing: Skips if transcript already exists"
echo "• Exponential backoff: Retries FastAPI up to 3 times (1s, 2s, 4s delays)"
echo "• FastAPI first: Routes to FastAPI if available (low latency)"
echo "• SQS fallback: Falls back to SQS queue if FastAPI fails after retries"
echo "• Auto session combination: Creates session transcripts when chunks complete"

# Load next-step helper and show next step
if [ -f "$(dirname "$0")/next-step-helper.sh" ]; then
    source "$(dirname "$0")/next-step-helper.sh"
    show_next_step "$0" "$(dirname "$0")"
fi