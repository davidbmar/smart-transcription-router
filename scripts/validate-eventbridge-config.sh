#!/bin/bash

# validate-eventbridge-config.sh - Validate EventBridge configuration across AWS, discovery, and .env

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}🔍 EventBridge Configuration Validator${NC}"
echo -e "${BLUE}======================================${NC}"
echo

# Step 1: List all buses in AWS
echo -e "${CYAN}[STEP 1]${NC} Listing EventBridge buses in AWS..."
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

AWS_BUSES=$(aws events list-event-buses --query 'EventBuses[*].Name' --output text 2>/dev/null || echo "")
CUSTOM_BUSES=$(aws events list-event-buses --output json 2>/dev/null | grep -E '"Name"' | grep -v default | cut -d'"' -f4 || echo "")

if [ -n "$AWS_BUSES" ]; then
    echo -e "${GREEN}✓${NC} Found buses in AWS:"
    for bus in $AWS_BUSES; do
        if [ "$bus" = "default" ]; then
            echo "  • $bus ${CYAN}(AWS default)${NC}"
        else
            # Get creation time for custom bus
            CREATION_TIME=$(aws events describe-event-bus --name "$bus" --query 'CreationTime' --output text 2>/dev/null || echo "unknown")
            echo "  • $bus ${GREEN}(custom - created: ${CREATION_TIME})${NC}"
        fi
    done
else
    echo -e "${RED}✗${NC} No buses found in AWS (check permissions)"
fi

echo

# Step 2: Check discovery sources
echo -e "${CYAN}[STEP 2]${NC} Checking discovery sources..."
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

DISCOVERED_BUSES=""

# Check eventbridge-orchestrator
if [ -f "../eventbridge-orchestrator/.env" ]; then
    EB_BUS=$(grep "^EVENT_BUS_NAME=" ../eventbridge-orchestrator/.env 2>/dev/null | cut -d'=' -f2 | tr -d '"')
    if [ -n "$EB_BUS" ]; then
        echo -e "${GREEN}✓${NC} eventbridge-orchestrator/.env: ${MAGENTA}$EB_BUS${NC}"
        DISCOVERED_BUSES="$DISCOVERED_BUSES $EB_BUS"
    else
        echo -e "${YELLOW}○${NC} eventbridge-orchestrator/.env: No EVENT_BUS_NAME found"
    fi
else
    echo -e "${YELLOW}○${NC} eventbridge-orchestrator/.env: File not found"
fi

# Check cognito project
if [ -f "../cognito-lambda-s3-webserver-cloudfront/.env" ]; then
    COGNITO_BUS=$(grep "^EVENT_BUS_NAME=" ../cognito-lambda-s3-webserver-cloudfront/.env 2>/dev/null | cut -d'=' -f2 | tr -d '"')
    if [ -n "$COGNITO_BUS" ]; then
        echo -e "${GREEN}✓${NC} cognito-lambda-s3/.env: ${MAGENTA}$COGNITO_BUS${NC}"
        DISCOVERED_BUSES="$DISCOVERED_BUSES $COGNITO_BUS"
    else
        echo -e "${YELLOW}○${NC} cognito-lambda-s3/.env: No EVENT_BUS_NAME found"
    fi
else
    echo -e "${YELLOW}○${NC} cognito-lambda-s3/.env: File not found"
fi

echo

# Step 3: Check current .env
echo -e "${CYAN}[STEP 3]${NC} Checking current project .env..."
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

CURRENT_ENV_BUS=""
if [ -f ".env" ]; then
    # Source the file to get the exported value
    source .env 2>/dev/null
    if [ -n "$EVENT_BUS_NAME" ]; then
        CURRENT_ENV_BUS="$EVENT_BUS_NAME"
        echo -e "${GREEN}✓${NC} Current .env: ${MAGENTA}$EVENT_BUS_NAME${NC}"
    else
        echo -e "${RED}✗${NC} Current .env: EVENT_BUS_NAME is empty or not set"
    fi
else
    echo -e "${RED}✗${NC} Current .env: File not found"
fi

echo

# Step 4: Validation Summary
echo -e "${CYAN}[STEP 4]${NC} Validation Summary..."
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

VALIDATION_PASSED=true
ISSUES=()

# Check if current .env value exists in AWS
if [ -n "$CURRENT_ENV_BUS" ]; then
    if echo "$AWS_BUSES" | grep -q "$CURRENT_ENV_BUS"; then
        echo -e "${GREEN}✓${NC} .env bus '$CURRENT_ENV_BUS' exists in AWS"
    else
        echo -e "${RED}✗${NC} .env bus '$CURRENT_ENV_BUS' NOT found in AWS!"
        VALIDATION_PASSED=false
        ISSUES+=("Bus in .env not found in AWS")
    fi
else
    echo -e "${RED}✗${NC} No EVENT_BUS_NAME configured in .env"
    VALIDATION_PASSED=false
    ISSUES+=("Missing EVENT_BUS_NAME in .env")
fi

# Check consistency across discovery sources
UNIQUE_BUSES=$(echo $DISCOVERED_BUSES | tr ' ' '\n' | sort -u | tr '\n' ' ')
BUS_COUNT=$(echo $UNIQUE_BUSES | wc -w)

if [ "$BUS_COUNT" -gt 1 ]; then
    echo -e "${YELLOW}⚠${NC} Multiple different buses discovered: $UNIQUE_BUSES"
    ISSUES+=("Inconsistent bus names across projects")
elif [ "$BUS_COUNT" -eq 1 ]; then
    DISCOVERED_BUS=$(echo $UNIQUE_BUSES | tr -d ' ')
    if [ "$DISCOVERED_BUS" = "$CURRENT_ENV_BUS" ]; then
        echo -e "${GREEN}✓${NC} All configurations consistent: $DISCOVERED_BUS"
    else
        echo -e "${YELLOW}⚠${NC} .env ($CURRENT_ENV_BUS) differs from discovered ($DISCOVERED_BUS)"
        ISSUES+=("Mismatch between .env and discovered bus")
    fi
fi

# Check for Lambda configuration
echo
echo -e "${CYAN}[BONUS]${NC} Lambda Router Configuration..."
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ -f ".env" ]; then
    source .env 2>/dev/null
    if [ -n "$TRANSCRIPTION_ROUTER_FUNCTION_NAME" ]; then
        echo -e "${GREEN}✓${NC} Lambda function configured: $TRANSCRIPTION_ROUTER_FUNCTION_NAME"
        
        # Check if Lambda exists in AWS
        if aws lambda get-function --function-name "$TRANSCRIPTION_ROUTER_FUNCTION_NAME" &>/dev/null; then
            echo -e "${GREEN}✓${NC} Lambda function exists in AWS"
            
            # Check if EventBridge rule exists
            RULE_NAME="${QUEUE_PREFIX}-audio-upload-rule"
            if aws events describe-rule --name "$RULE_NAME" --event-bus-name "$EVENT_BUS_NAME" &>/dev/null; then
                echo -e "${GREEN}✓${NC} EventBridge rule '$RULE_NAME' exists"
            else
                echo -e "${YELLOW}○${NC} EventBridge rule '$RULE_NAME' not found (run step-341)"
            fi
        else
            echo -e "${RED}✗${NC} Lambda function NOT found in AWS!"
            ISSUES+=("Lambda function not deployed")
        fi
    else
        echo -e "${YELLOW}○${NC} Lambda function not configured (run step-340)"
    fi
fi

echo
echo -e "${BLUE}======================================${NC}"

if [ "$VALIDATION_PASSED" = true ] && [ ${#ISSUES[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ VALIDATION PASSED${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo
    echo "All EventBridge configurations are properly aligned:"
    echo "  • Bus exists in AWS: ✓"
    echo "  • Configurations consistent: ✓"
    echo "  • .env properly configured: ✓"
else
    echo -e "${RED}❌ VALIDATION FAILED${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo
    echo -e "${YELLOW}Issues found:${NC}"
    for issue in "${ISSUES[@]}"; do
        echo "  • $issue"
    done
    echo
    echo -e "${CYAN}Recommendations:${NC}"
    
    if [ -n "$DISCOVERED_BUS" ] && [ "$DISCOVERED_BUS" != "$CURRENT_ENV_BUS" ]; then
        echo "  1. Update .env to use discovered bus:"
        echo "     export EVENT_BUS_NAME=\"$DISCOVERED_BUS\""
    fi
    
    if [ -z "$CURRENT_ENV_BUS" ] && [ -n "$CUSTOM_BUSES" ]; then
        echo "  1. Set EVENT_BUS_NAME in .env:"
        echo "     export EVENT_BUS_NAME=\"$CUSTOM_BUSES\""
    fi
    
    echo "  2. Run: ./scripts/step-341-configure-eventbridge-trigger.sh"
fi

echo
echo -e "${CYAN}[TIP]${NC} To fix configuration issues, run:"
echo "  ./scripts/step-341-configure-eventbridge-trigger.sh"
echo "  (It will auto-discover and update your configuration)"
echo