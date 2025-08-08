#!/bin/bash

# discover-event-bus.sh - Intelligent EventBridge bus discovery
# This script attempts multiple methods to find the correct EVENT_BUS_NAME

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 EventBridge Bus Discovery${NC}"
echo -e "${BLUE}======================================${NC}"

DISCOVERED_BUS=""
DISCOVERY_METHOD=""

# Method 1: Check current .env file
if [ -f ".env" ] && grep -q "EVENT_BUS_NAME=" .env; then
    source .env
    if [ -n "$EVENT_BUS_NAME" ]; then
        echo -e "${GREEN}✓${NC} Found in current .env: $EVENT_BUS_NAME"
        DISCOVERED_BUS="$EVENT_BUS_NAME"
        DISCOVERY_METHOD="current .env"
    fi
fi

# Method 2: Check parent directories for related projects
if [ -z "$DISCOVERED_BUS" ]; then
    echo -e "${CYAN}[SCANNING]${NC} Checking parent directories..."
    
    # Look for eventbridge-orchestrator project specifically
    if [ -f "../eventbridge-orchestrator/.env" ]; then
        EVENT_BUS_FROM_PARENT=$(grep "^EVENT_BUS_NAME=" ../eventbridge-orchestrator/.env 2>/dev/null | cut -d'=' -f2 | tr -d '"')
        if [ -n "$EVENT_BUS_FROM_PARENT" ]; then
            echo -e "${GREEN}✓${NC} Found in eventbridge-orchestrator: $EVENT_BUS_FROM_PARENT"
            DISCOVERED_BUS="$EVENT_BUS_FROM_PARENT"
            DISCOVERY_METHOD="eventbridge-orchestrator project"
        fi
    fi
    
    # Check cognito project
    if [ -z "$DISCOVERED_BUS" ] && [ -f "../cognito-lambda-s3-webserver-cloudfront/.env" ]; then
        EVENT_BUS_FROM_COGNITO=$(grep "^EVENT_BUS_NAME=" ../cognito-lambda-s3-webserver-cloudfront/.env 2>/dev/null | cut -d'=' -f2 | tr -d '"')
        if [ -n "$EVENT_BUS_FROM_COGNITO" ]; then
            echo -e "${GREEN}✓${NC} Found in cognito project: $EVENT_BUS_FROM_COGNITO"
            DISCOVERED_BUS="$EVENT_BUS_FROM_COGNITO"
            DISCOVERY_METHOD="cognito project"
        fi
    fi
fi

# Method 3: List existing EventBridge buses from AWS
if [ -z "$DISCOVERED_BUS" ]; then
    echo -e "${CYAN}[AWS QUERY]${NC} Listing EventBridge buses..."
    
    # Get list of custom event buses
    AVAILABLE_BUSES=$(aws events list-event-buses \
        --query 'EventBuses[?Name!=`default`].Name' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$AVAILABLE_BUSES" ]; then
        echo -e "${BLUE}Available custom event buses:${NC}"
        echo "$AVAILABLE_BUSES" | tr '\t' '\n' | while read bus; do
            echo "  • $bus"
        done
        
        # Check if only one custom bus exists
        BUS_COUNT=$(echo "$AVAILABLE_BUSES" | wc -w)
        if [ "$BUS_COUNT" -eq 1 ]; then
            echo -e "${GREEN}✓${NC} Only one custom bus found: $AVAILABLE_BUSES"
            DISCOVERED_BUS="$AVAILABLE_BUSES"
            DISCOVERY_METHOD="AWS (single bus)"
        else
            # Try to match based on environment pattern
            if [ -n "$ENVIRONMENT" ]; then
                PATTERN_MATCH=$(echo "$AVAILABLE_BUSES" | tr '\t' '\n' | grep -E "^${ENVIRONMENT}-" | head -1)
                if [ -n "$PATTERN_MATCH" ]; then
                    echo -e "${GREEN}✓${NC} Pattern match for environment '$ENVIRONMENT': $PATTERN_MATCH"
                    DISCOVERED_BUS="$PATTERN_MATCH"
                    DISCOVERY_METHOD="AWS (pattern match)"
                fi
            fi
        fi
    fi
fi

# Method 4: Convention-based guess
if [ -z "$DISCOVERED_BUS" ] && [ -n "$ENVIRONMENT" ]; then
    CONVENTION_BUS="${ENVIRONMENT}-application-events"
    echo -e "${CYAN}[CONVENTION]${NC} Checking standard name: $CONVENTION_BUS"
    
    # Verify it exists
    if aws events describe-event-bus --name "$CONVENTION_BUS" &>/dev/null; then
        echo -e "${GREEN}✓${NC} Convention-based bus exists: $CONVENTION_BUS"
        DISCOVERED_BUS="$CONVENTION_BUS"
        DISCOVERY_METHOD="naming convention"
    fi
fi

# Display results
echo
echo -e "${BLUE}======================================${NC}"
if [ -n "$DISCOVERED_BUS" ]; then
    echo -e "${GREEN}✅ EventBridge Bus Discovered${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo
    echo -e "${GREEN}[RESULT]${NC}"
    echo "  Bus Name: $DISCOVERED_BUS"
    echo "  Method: $DISCOVERY_METHOD"
    echo
    echo -e "${YELLOW}[TO USE THIS BUS]${NC}"
    echo "  Add to .env file:"
    echo "  export EVENT_BUS_NAME=\"$DISCOVERED_BUS\""
    echo
    
    # Optionally update .env
    read -p "Would you like to update .env with this bus name? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if grep -q "^export EVENT_BUS_NAME=" .env 2>/dev/null; then
            sed -i "s/^export EVENT_BUS_NAME=.*/export EVENT_BUS_NAME=\"$DISCOVERED_BUS\"/" .env
        else
            echo "export EVENT_BUS_NAME=\"$DISCOVERED_BUS\"" >> .env
        fi
        echo -e "${GREEN}✓${NC} Updated .env file"
    fi
    
    # Export for current session
    export EVENT_BUS_NAME="$DISCOVERED_BUS"
else
    echo -e "${YELLOW}⚠️  No EventBridge Bus Found${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo
    echo "Could not automatically discover EVENT_BUS_NAME"
    echo
    echo -e "${CYAN}[MANUAL OPTIONS]${NC}"
    echo "1. Check if EventBridge is set up in your AWS account"
    echo "2. Run the eventbridge-orchestrator setup:"
    echo "   cd ../eventbridge-orchestrator && ./step-10-deploy.sh"
    echo "3. Manually specify the bus name in .env"
    echo
    exit 1
fi