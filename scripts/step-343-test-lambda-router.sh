#!/bin/bash

# step-342-test-lambda-router.sh - Test Lambda router functionality

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
echo -e "${BLUE}🧪 Test Lambda Router${NC}"
echo -e "${BLUE}======================================${NC}"
echo

# Verify Lambda function exists
if [ -z "$TRANSCRIPTION_ROUTER_FUNCTION_NAME" ]; then
    echo -e "${RED}[ERROR]${NC} Lambda function not found. Run step-340-deploy-lambda-router.sh first."
    exit 1
fi

echo -e "${GREEN}[STEP 1]${NC} Testing Lambda with mock audio upload event..."

# Create test event payload
TEST_EVENT='{
    "version": "0",
    "id": "test-event-id",
    "detail-type": "Audio Upload Completed",
    "source": "audio.upload",
    "account": "123456789012",
    "time": "2023-01-01T00:00:00Z",
    "region": "us-east-1",
    "detail": {
        "user_id": "test-user",
        "email": "test@example.com",
        "file_name": "test-audio.webm",
        "s3_bucket": "test-bucket",
        "s3_key": "audio/test-audio.webm",
        "content_type": "audio/webm",
        "file_size": 1024,
        "event_type": "audio_upload"
    }
}'

echo -e "${YELLOW}[INFO]${NC} Invoking Lambda function with test event..."
echo "Function: $TRANSCRIPTION_ROUTER_FUNCTION_NAME"

# Invoke Lambda function
RESULT=$(aws lambda invoke \
    --function-name "$TRANSCRIPTION_ROUTER_FUNCTION_NAME" \
    --payload "$TEST_EVENT" \
    --cli-binary-format raw-in-base64-out \
    --region "$AWS_REGION" \
    /tmp/lambda-response.json 2>&1)

# Check if invocation was successful
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Lambda invocation successful${NC}"
    
    # Display response
    echo -e "${BLUE}Response:${NC}"
    cat /tmp/lambda-response.json | jq .
    
    # Check response content
    RESPONSE_BODY=$(cat /tmp/lambda-response.json)
    if echo "$RESPONSE_BODY" | grep -q "direct"; then
        echo -e "${GREEN}✓ Router chose direct FastAPI processing${NC}"
    elif echo "$RESPONSE_BODY" | grep -q "sqs"; then
        echo -e "${GREEN}✓ Router chose SQS queue processing${NC}"
    else
        echo -e "${YELLOW}⚠ Unexpected router response${NC}"
    fi
else
    echo -e "${RED}✗ Lambda invocation failed${NC}"
    echo "$RESULT"
fi

echo -e "${GREEN}[STEP 2]${NC} Testing with force_batch flag..."

# Test with force_batch flag
BATCH_EVENT='{
    "version": "0",
    "id": "test-batch-event-id",
    "detail-type": "Audio Upload Completed",
    "source": "audio.upload",
    "account": "123456789012",
    "time": "2023-01-01T00:00:00Z",
    "region": "us-east-1",
    "detail": {
        "user_id": "test-user",
        "email": "test@example.com",
        "file_name": "test-audio-batch.webm",
        "s3_bucket": "test-bucket",
        "s3_key": "audio/test-audio-batch.webm",
        "content_type": "audio/webm",
        "file_size": 1024,
        "event_type": "audio_upload",
        "force_batch": true
    }
}'

echo -e "${YELLOW}[INFO]${NC} Testing with force_batch=true..."

aws lambda invoke \
    --function-name "$TRANSCRIPTION_ROUTER_FUNCTION_NAME" \
    --payload "$BATCH_EVENT" \
    --cli-binary-format raw-in-base64-out \
    --region "$AWS_REGION" \
    /tmp/lambda-batch-response.json

echo -e "${BLUE}Batch Response:${NC}"
cat /tmp/lambda-batch-response.json | jq .

echo -e "${GREEN}[STEP 3]${NC} Checking Lambda logs..."

# Get recent logs
echo -e "${YELLOW}[INFO]${NC} Recent Lambda execution logs:"
aws logs filter-log-events \
    --log-group-name "/aws/lambda/$TRANSCRIPTION_ROUTER_FUNCTION_NAME" \
    --start-time $(date -d "5 minutes ago" +%s)000 \
    --query 'events[*].message' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "No recent logs found"

echo -e "${GREEN}[STEP 4]${NC} Checking FastAPI server status..."

# Check if FastAPI servers are running
FAST_API_INSTANCES=$(aws ec2 describe-instances \
    --filters "Name=tag:Type,Values=fast-api-worker" "Name=instance-state-name,Values=running" \
    --region "$AWS_REGION" \
    --query 'Reservations[*].Instances[*].[InstanceId,PublicIpAddress]' \
    --output json)

if [ "$FAST_API_INSTANCES" = "[]" ]; then
    echo -e "${YELLOW}⚠ No FastAPI servers running - requests will go to SQS${NC}"
else
    INSTANCE_ID=$(echo "$FAST_API_INSTANCES" | jq -r '.[0][0][0]')
    PUBLIC_IP=$(echo "$FAST_API_INSTANCES" | jq -r '.[0][0][1]')
    echo -e "${GREEN}✓ FastAPI server found: $INSTANCE_ID ($PUBLIC_IP)${NC}"
    
    # Test server health
    if curl -f -s --max-time 3 "http://$PUBLIC_IP:8000/health" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ FastAPI server is healthy${NC}"
        echo -e "${YELLOW}[INFO]${NC} Router should choose direct processing"
    else
        echo -e "${YELLOW}⚠ FastAPI server not responding${NC}"
        echo -e "${YELLOW}[INFO]${NC} Router should choose SQS processing"
    fi
fi

# Clean up temp files
rm -f /tmp/lambda-response.json /tmp/lambda-batch-response.json

echo
echo -e "${BLUE}======================================${NC}"
echo -e "${GREEN}✅ Lambda Router Test Complete${NC}"
echo -e "${BLUE}======================================${NC}"
echo
echo -e "${GREEN}[ROUTER BEHAVIOR]${NC}"
echo "• Checks for running FastAPI instances"
echo "• Tests server health before routing"
echo "• Falls back to SQS if server unavailable"
echo "• Respects force_batch flag"
echo
echo -e "${GREEN}[NEXT STEPS]${NC}"
echo "1. Upload audio in cognito-lambda-s3-webserver-cloudfront"
echo "2. Monitor CloudWatch logs for routing decisions"
echo "3. Create batch processor for scheduled runs"
echo
echo -e "${YELLOW}[MONITORING]${NC}"
echo "CloudWatch Logs: /aws/lambda/$TRANSCRIPTION_ROUTER_FUNCTION_NAME"
echo "SQS Queue: $SQS_QUEUE_URL"
# Load next-step helper and show next step
if [ -f "$(dirname "$0")/next-step-helper.sh" ]; then
    source "$(dirname "$0")/next-step-helper.sh"
    show_next_step "$0" "$(dirname "$0")"
fi
