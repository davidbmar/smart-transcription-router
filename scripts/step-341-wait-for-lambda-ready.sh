#!/bin/bash

# step-340a-wait-for-lambda-ready.sh - Wait for Lambda function to be fully ready
# This script waits for the Lambda function to be active and ready for EventBridge configuration
# Prerequisites: step-340 (Lambda deployment)
# Outputs: Confirmation that Lambda is ready

# Source framework libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/error-handling.sh" ]; then
    source "$SCRIPT_DIR/error-handling.sh"
else
    echo "Error handling library not found, using basic error handling"
    set -e
fi

if [ -f "$SCRIPT_DIR/step-navigation.sh" ]; then
    source "$SCRIPT_DIR/step-navigation.sh"
fi

# Initialize script
SCRIPT_NAME="step-340a-wait-for-lambda-ready"
setup_error_handling "$SCRIPT_NAME"
create_checkpoint "$SCRIPT_NAME" "in_progress" "$SCRIPT_NAME"

# Show step purpose
if declare -f show_step_purpose > /dev/null 2>&1; then
    show_step_purpose "$0"
fi

# Get the project root directory (parent of scripts directory)
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.env"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    log_info "Configuration loaded" "$SCRIPT_NAME"
else
    log_error "Configuration file not found at $CONFIG_FILE" "$SCRIPT_NAME"
    exit 1
fi

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}⏳ Wait for Lambda Function Ready${NC}"
echo -e "${BLUE}======================================${NC}"
echo

# Set the Lambda function name
LAMBDA_FUNCTION_NAME="${LAMBDA_FUNCTION_NAME:-${QUEUE_PREFIX}-transcription-router}"

# Check if Lambda function exists
echo -e "${GREEN}[CHECKING]${NC} Lambda function: $LAMBDA_FUNCTION_NAME"

MAX_WAIT_TIME=120  # Maximum wait time in seconds
WAIT_INTERVAL=5    # Check interval in seconds
ELAPSED_TIME=0

while [ $ELAPSED_TIME -lt $MAX_WAIT_TIME ]; do
    # Check if function exists and get its state
    FUNCTION_STATE=$(aws lambda get-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --region "$AWS_REGION" \
        --query 'Configuration.State' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    UPDATE_STATUS=$(aws lambda get-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --region "$AWS_REGION" \
        --query 'Configuration.LastUpdateStatus' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$FUNCTION_STATE" = "Active" ] && [ "$UPDATE_STATUS" = "Successful" ]; then
        echo -e "${GREEN}✅ Lambda function is active and ready!${NC}"
        
        # Get function details
        FUNCTION_ARN=$(aws lambda get-function \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --region "$AWS_REGION" \
            --query 'Configuration.FunctionArn' \
            --output text)
        
        echo -e "${GREEN}[DETAILS]${NC}"
        echo "  Function Name: $LAMBDA_FUNCTION_NAME"
        echo "  Function ARN: $FUNCTION_ARN"
        echo "  State: $FUNCTION_STATE"
        echo "  Update Status: $UPDATE_STATUS"
        
        # Test invocation with a simple test event
        echo
        echo -e "${GREEN}[TESTING]${NC} Lambda invocation..."
        
        TEST_PAYLOAD='{"test": true, "source": "step-340a"}'
        TEST_RESPONSE=$(aws lambda invoke \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --region "$AWS_REGION" \
            --cli-binary-format raw-in-base64-out \
            --payload "$TEST_PAYLOAD" \
            /tmp/lambda-test-response.json 2>&1 | grep StatusCode || echo "")
        
        if echo "$TEST_RESPONSE" | grep -q "200\|202"; then
            echo -e "${GREEN}✅ Lambda responds to invocations${NC}"
        else
            log_warning "Lambda invocation test returned unexpected status" "$SCRIPT_NAME"
        fi
        
        # Update .env with Lambda details if not already set
        if [ -z "$TRANSCRIPTION_ROUTER_LAMBDA_ARN" ]; then
            echo "export TRANSCRIPTION_ROUTER_LAMBDA_ARN=\"$FUNCTION_ARN\"" >> "$CONFIG_FILE"
            log_info "Updated .env with Lambda ARN" "$SCRIPT_NAME"
        fi
        
        if [ -z "$TRANSCRIPTION_ROUTER_FUNCTION_NAME" ]; then
            echo "export TRANSCRIPTION_ROUTER_FUNCTION_NAME=\"$LAMBDA_FUNCTION_NAME\"" >> "$CONFIG_FILE"
            log_info "Updated .env with Lambda function name" "$SCRIPT_NAME"
        fi
        
        log_success "Lambda function is ready for EventBridge configuration" "$SCRIPT_NAME"
        create_checkpoint "$SCRIPT_NAME" "completed" "$SCRIPT_NAME"
        
        echo
        echo -e "${BLUE}======================================${NC}"
        echo -e "${GREEN}✅ Lambda Function Ready${NC}"
        echo -e "${BLUE}======================================${NC}"
        echo
        echo -e "${GREEN}[STATUS]${NC} Lambda function is active and responding"
        echo -e "${GREEN}[READY]${NC} You can now configure EventBridge triggers"
        echo
        
        # Show next step
        echo
        echo -e "${BLUE}======================================${NC}"
        echo -e "${GREEN}🎯 NEXT STEP${NC}"
        echo -e "${BLUE}======================================${NC}"
        echo -e "${BLUE}Run:${NC} ./scripts/step-342-configure-eventbridge-trigger.sh"
        echo -e "${CYAN}Purpose:${NC} Configure EventBridge to trigger Lambda on audio uploads"
        echo
        exit 0
        
    elif [ "$FUNCTION_STATE" = "NOT_FOUND" ]; then
        echo -e "${RED}❌ Lambda function not found${NC}"
        echo -e "${YELLOW}Please run: ./scripts/step-340-deploy-lambda-router.sh${NC}"
        exit 1
        
    elif [ "$FUNCTION_STATE" = "Pending" ] || [ "$UPDATE_STATUS" = "InProgress" ]; then
        echo -e "${YELLOW}⏳ Lambda function is being created/updated...${NC}"
        echo "  State: $FUNCTION_STATE"
        echo "  Update Status: $UPDATE_STATUS"
        echo "  Waiting ${WAIT_INTERVAL} seconds... (${ELAPSED_TIME}/${MAX_WAIT_TIME}s)"
        
    elif [ "$FUNCTION_STATE" = "Failed" ] || [ "$UPDATE_STATUS" = "Failed" ]; then
        echo -e "${RED}❌ Lambda function deployment failed${NC}"
        echo -e "${YELLOW}Please check CloudWatch logs and retry step-340${NC}"
        exit 1
        
    else
        echo -e "${YELLOW}⚠️  Unexpected state: $FUNCTION_STATE / $UPDATE_STATUS${NC}"
        echo "  Waiting ${WAIT_INTERVAL} seconds... (${ELAPSED_TIME}/${MAX_WAIT_TIME}s)"
    fi
    
    sleep $WAIT_INTERVAL
    ELAPSED_TIME=$((ELAPSED_TIME + WAIT_INTERVAL))
done

# If we get here, we've timed out
log_error "Timeout waiting for Lambda function to be ready after ${MAX_WAIT_TIME} seconds" "$SCRIPT_NAME"
echo -e "${YELLOW}Please check the Lambda function status manually:${NC}"
echo "  aws lambda get-function --function-name $LAMBDA_FUNCTION_NAME --region $AWS_REGION"
exit 1