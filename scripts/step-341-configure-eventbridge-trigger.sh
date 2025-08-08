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
    echo -e "${CYAN}[EVENT BUS CONFIGURATION]${NC}"
    echo "Choose how to specify the EventBridge bus:"
    echo "  1) Automatic discovery (recommended)"
    echo "  2) Manual input"
    echo -n "Select option [1-2]: "
    read -r OPTION
    
    if [ "$OPTION" = "2" ]; then
        # Manual input
        echo -e "${YELLOW}[MANUAL INPUT]${NC}"
        
        # List available buses from AWS for reference
        echo "Available EventBridge buses in AWS:"
        aws events list-event-buses --query 'EventBuses[?Name!=`default`].Name' --output table 2>/dev/null || echo "  (unable to list)"
        
        echo -n "Enter the EventBridge bus name (e.g., dev-application-events): "
        read -r EVENT_BUS_NAME
        
        if [ -z "$EVENT_BUS_NAME" ]; then
            echo -e "${RED}[ERROR]${NC} Bus name cannot be empty"
            exit 1
        fi
        
        echo -e "${GREEN}[SELECTED]${NC} Using manually entered bus: $EVENT_BUS_NAME"
    else
        # Automatic discovery (default)
        echo -e "${CYAN}[DISCOVERY]${NC} Starting automatic bus discovery..."
        
        # First, show what's available in AWS
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}[AWS]${NC} EventBridge buses in your account:"
        AWS_BUSES=$(aws events list-event-buses --query 'EventBuses[*].Name' --output text 2>/dev/null || echo "")
        if [ -n "$AWS_BUSES" ]; then
            for bus in $AWS_BUSES; do
                if [ "$bus" = "default" ]; then
                    echo "  • $bus (AWS default - not for custom events)"
                else
                    echo -e "  • ${GREEN}$bus${NC} (custom bus)"
                fi
            done
        else
            echo "  (Unable to list - check AWS permissions)"
        fi
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo
        
        DISCOVERED_BUS=""
        DISCOVERY_SOURCE=""
        
        # Method 1: Check eventbridge-orchestrator project (most reliable)
        if [ -f "../eventbridge-orchestrator/.env" ]; then
            DISCOVERED_BUS=$(grep "^EVENT_BUS_NAME=" ../eventbridge-orchestrator/.env 2>/dev/null | cut -d'=' -f2 | tr -d '"')
            if [ -n "$DISCOVERED_BUS" ]; then
                DISCOVERY_SOURCE="eventbridge-orchestrator project"
                echo -e "${GREEN}✓${NC} Found in eventbridge-orchestrator: $DISCOVERED_BUS"
            fi
        fi
        
        # Method 2: Check cognito project
        if [ -z "$DISCOVERED_BUS" ] && [ -f "../cognito-lambda-s3-webserver-cloudfront/.env" ]; then
            DISCOVERED_BUS=$(grep "^EVENT_BUS_NAME=" ../cognito-lambda-s3-webserver-cloudfront/.env 2>/dev/null | cut -d'=' -f2 | tr -d '"')
            if [ -n "$DISCOVERED_BUS" ]; then
                DISCOVERY_SOURCE="cognito project"
                echo -e "${GREEN}✓${NC} Found in cognito project: $DISCOVERED_BUS"
            fi
        fi
        
        # Method 3: Check AWS for single bus or environment pattern
        if [ -z "$DISCOVERED_BUS" ]; then
            echo -e "${CYAN}[AWS]${NC} Checking AWS for existing buses..."
            AVAILABLE_BUSES=$(aws events list-event-buses \
                --query 'EventBuses[?Name!=`default`].Name' \
                --output text 2>/dev/null || echo "")
            
            if [ -n "$AVAILABLE_BUSES" ]; then
                BUS_COUNT=$(echo "$AVAILABLE_BUSES" | wc -w)
                if [ "$BUS_COUNT" -eq 1 ]; then
                    DISCOVERED_BUS="$AVAILABLE_BUSES"
                    DISCOVERY_SOURCE="AWS (single custom bus)"
                    echo -e "${GREEN}✓${NC} Found single custom bus in AWS: $DISCOVERED_BUS"
                elif [ -n "$ENVIRONMENT" ]; then
                    # Try to match based on environment
                    PATTERN_MATCH=$(echo "$AVAILABLE_BUSES" | tr '\t' '\n' | grep -E "^${ENVIRONMENT}-" | head -1)
                    if [ -n "$PATTERN_MATCH" ]; then
                        DISCOVERED_BUS="$PATTERN_MATCH"
                        DISCOVERY_SOURCE="AWS (environment pattern match)"
                        echo -e "${GREEN}✓${NC} Found pattern match for '$ENVIRONMENT': $DISCOVERED_BUS"
                    fi
                fi
            fi
        fi
        
        # Method 4: Convention-based guess
        if [ -z "$DISCOVERED_BUS" ] && [ -n "$ENVIRONMENT" ]; then
            CONVENTION_BUS="${ENVIRONMENT}-application-events"
            if aws events describe-event-bus --name "$CONVENTION_BUS" &>/dev/null; then
                DISCOVERED_BUS="$CONVENTION_BUS"
                DISCOVERY_SOURCE="naming convention"
                echo -e "${GREEN}✓${NC} Found via convention: $DISCOVERED_BUS"
            fi
        fi
        
        # Show discovery summary
        echo
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}[DISCOVERY SUMMARY]${NC}"
        
        # Check all sources and display results
        EB_BUS=$([ -f "../eventbridge-orchestrator/.env" ] && grep "^EVENT_BUS_NAME=" ../eventbridge-orchestrator/.env 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "")
        COGNITO_BUS=$([ -f "../cognito-lambda-s3-webserver-cloudfront/.env" ] && grep "^EVENT_BUS_NAME=" ../cognito-lambda-s3-webserver-cloudfront/.env 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "")
        CURRENT_BUS=$([ -f ".env" ] && grep "^export EVENT_BUS_NAME=" .env 2>/dev/null | cut -d'"' -f2 || echo "")
        
        echo "  EventBridge Orchestrator: ${EB_BUS:-not found}"
        echo "  Cognito Project:          ${COGNITO_BUS:-not found}"
        echo "  Current .env:             ${CURRENT_BUS:-not configured}"
        echo "  AWS Custom Bus:           $(echo "$AWS_BUSES" | tr '\t' '\n' | grep -v default | head -1 || echo "none")"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        # Use discovered bus or ask for manual input
        if [ -n "$DISCOVERED_BUS" ]; then
            echo
            echo -e "${GREEN}[RECOMMENDED]${NC} Based on discovery: $DISCOVERED_BUS"
            echo -e "${CYAN}[SOURCE]${NC} $DISCOVERY_SOURCE"
            
            # Validate it exists in AWS
            if echo "$AWS_BUSES" | grep -q "$DISCOVERED_BUS"; then
                echo -e "${GREEN}✓${NC} Verified: This bus exists in AWS"
            else
                echo -e "${YELLOW}⚠${NC} Warning: This bus was not found in AWS listing"
            fi
            
            echo -n "Use this bus? [Y/n]: "
            read -r CONFIRM
            
            if [ "$CONFIRM" = "n" ] || [ "$CONFIRM" = "N" ]; then
                echo -n "Enter the EventBridge bus name manually: "
                read -r EVENT_BUS_NAME
            else
                EVENT_BUS_NAME="$DISCOVERED_BUS"
            fi
        else
            echo -e "${YELLOW}[NOT FOUND]${NC} Could not auto-discover EventBridge bus"
            echo "Available buses in AWS:"
            aws events list-event-buses --query 'EventBuses[?Name!=`default`].Name' --output table 2>/dev/null || echo "  (unable to list)"
            echo -n "Enter the EventBridge bus name: "
            read -r EVENT_BUS_NAME
        fi
    fi
    
    # Validate and save the bus name
    if [ -n "$EVENT_BUS_NAME" ]; then
        # Verify the bus exists in AWS
        if aws events describe-event-bus --name "$EVENT_BUS_NAME" &>/dev/null; then
            echo -e "${GREEN}✓${NC} Verified bus exists in AWS"
        else
            echo -e "${YELLOW}[WARNING]${NC} Could not verify bus exists in AWS (may be permissions issue)"
        fi
        
        # Update .env file
        if grep -q "^export EVENT_BUS_NAME=" "$CONFIG_FILE" 2>/dev/null; then
            sed -i "s/^export EVENT_BUS_NAME=.*/export EVENT_BUS_NAME=\"$EVENT_BUS_NAME\"/" "$CONFIG_FILE"
        else
            echo "export EVENT_BUS_NAME=\"$EVENT_BUS_NAME\"" >> "$CONFIG_FILE"
        fi
        echo -e "${GREEN}[SAVED]${NC} EVENT_BUS_NAME=$EVENT_BUS_NAME added to .env"
    else
        echo -e "${RED}[ERROR]${NC} No EventBridge bus name specified"
        exit 1
    fi
fi

# Verify Lambda function exists
if [ -z "$TRANSCRIPTION_ROUTER_FUNCTION_NAME" ]; then
    echo -e "${RED}[ERROR]${NC} Lambda function not found. Run step-340-deploy-lambda-router.sh first."
    exit 1
fi

echo -e "${GREEN}[STEP 1]${NC} Creating EventBridge rule..."

RULE_NAME="${QUEUE_PREFIX}-audio-upload-rule"

# Create rule for audio upload events (supports both test and web app formats)
aws events put-rule \
    --name "$RULE_NAME" \
    --event-bus-name "$EVENT_BUS_NAME" \
    --event-pattern '{
        "source": ["audio.upload", "custom.upload-service"],
        "detail-type": ["Audio Upload Completed", "Audio Uploaded"]
    }' \
    --description "Route audio uploads to transcription router (test and web app events)" \
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
