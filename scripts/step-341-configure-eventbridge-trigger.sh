#!/bin/bash

# step-341-configure-eventbridge-trigger.sh - Configure EventBridge to trigger Lambda router

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
echo -e "${BLUE}🔗 Configure EventBridge Trigger${NC}"
echo -e "${BLUE}======================================${NC}"
echo

# Check for EventBridge bus name
if [ -z "$EVENT_BUS_NAME" ]; then
    echo -e "${YELLOW}[INPUT REQUIRED]${NC} Enter the EventBridge bus name (e.g., dev-application-events):"
    read -r EVENT_BUS_NAME
    echo "EVENT_BUS_NAME=$EVENT_BUS_NAME" >> "$CONFIG_FILE"
fi

# Verify Lambda function exists
if [ -z "$TRANSCRIPTION_ROUTER_FUNCTION_NAME" ]; then
    echo -e "${RED}[ERROR]${NC} Lambda function not found. Run step-340-deploy-lambda-router.sh first."
    exit 1
fi

echo -e "${GREEN}[STEP 1]${NC} Creating EventBridge rule..."

RULE_NAME="${QUEUE_PREFIX}-audio-upload-rule"

# Create rule for audio upload events
aws events put-rule \
    --name "$RULE_NAME" \
    --event-bus-name "$EVENT_BUS_NAME" \
    --event-pattern '{
        "source": ["audio.upload"],
        "detail-type": ["Audio Upload Completed"]
    }' \
    --description "Route audio uploads to transcription router" \
    --state ENABLED \
    --region "$AWS_REGION"

echo -e "${GREEN}[STEP 2]${NC} Adding Lambda permission for EventBridge..."

# Add permission for EventBridge to invoke Lambda
STATEMENT_ID="${RULE_NAME}-permission"
aws lambda add-permission \
    --function-name "$TRANSCRIPTION_ROUTER_FUNCTION_NAME" \
    --statement-id "$STATEMENT_ID" \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn "arn:aws:events:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):rule/${EVENT_BUS_NAME}/${RULE_NAME}" \
    --region "$AWS_REGION" 2>/dev/null || echo -e "${YELLOW}[INFO]${NC} Permission already exists"

echo -e "${GREEN}[STEP 3]${NC} Adding Lambda as target for the rule..."

# Add Lambda as target
aws events put-targets \
    --rule "$RULE_NAME" \
    --event-bus-name "$EVENT_BUS_NAME" \
    --targets "Id=1,Arn=$TRANSCRIPTION_ROUTER_LAMBDA_ARN" \
    --region "$AWS_REGION"

echo -e "${GREEN}[STEP 4]${NC} Creating scheduled rule for midnight batch processing..."

SCHEDULE_RULE_NAME="${QUEUE_PREFIX}-midnight-batch-rule"

# Create rule for midnight batch processing (UTC)
aws events put-rule \
    --name "$SCHEDULE_RULE_NAME" \
    --schedule-expression "cron(0 0 * * ? *)" \
    --description "Trigger batch transcription processing at midnight UTC" \
    --state ENABLED \
    --region "$AWS_REGION"

# Note: For the scheduled rule, we'll need a different Lambda that processes the SQS queue
echo -e "${YELLOW}[INFO]${NC} Scheduled rule created but needs a batch processor Lambda"

echo
echo -e "${BLUE}======================================${NC}"
echo -e "${GREEN}✅ EventBridge Configured${NC}"
echo -e "${BLUE}======================================${NC}"
echo
echo -e "${GREEN}[CONFIGURATION]${NC}"
echo "Event Bus: $EVENT_BUS_NAME"
echo "Audio Upload Rule: $RULE_NAME"
echo "Scheduled Rule: $SCHEDULE_RULE_NAME"
echo "Target Lambda: $TRANSCRIPTION_ROUTER_FUNCTION_NAME"
echo
echo -e "${GREEN}[EVENT PATTERN]${NC}"
echo "Source: audio.upload"
echo "Detail Type: Audio Upload Completed"
echo
echo -e "${GREEN}[NEXT STEPS]${NC}"
echo "1. Test the complete flow:"
echo "   ./scripts/step-342-test-lambda-router.sh"
echo
echo "2. Create batch processor for scheduled runs:"
echo "   ./scripts/step-343-create-batch-processor.sh"
echo
echo -e "${YELLOW}[TESTING]${NC}"
echo "Upload audio in cognito-lambda-s3-webserver-cloudfront"
echo "Events will now route through the smart router!"
# Load next-step helper and show next step
if [ -f "$(dirname "$0")/next-step-helper.sh" ]; then
    source "$(dirname "$0")/next-step-helper.sh"
    show_next_step "$0" "$(dirname "$0")"
fi
