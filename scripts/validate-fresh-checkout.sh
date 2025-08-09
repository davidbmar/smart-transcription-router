#!/bin/bash

# validate-fresh-checkout.sh - Validate that all prerequisites are in place for a fresh checkout
# This script checks that everything needed to run from a fresh GitHub checkout is present

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}🔍 Validating Fresh Checkout Setup${NC}"
echo -e "${BLUE}======================================${NC}"
echo

ERRORS=0
WARNINGS=0

# Check .env exists
echo -e "${GREEN}[CHECK 1]${NC} Configuration file..."
if [ -f ".env" ]; then
    echo -e "  ✅ .env file exists"
else
    if [ -f ".env.template" ]; then
        echo -e "  ⚠️  .env file missing but template exists"
        echo -e "  ${YELLOW}Run: cp .env.template .env && vi .env${NC}"
        WARNINGS=$((WARNINGS + 1))
    else
        echo -e "  ❌ Both .env and .env.template missing!"
        ERRORS=$((ERRORS + 1))
    fi
fi

# Check critical environment variables
echo -e "${GREEN}[CHECK 2]${NC} Critical environment variables..."
if [ -f ".env" ]; then
    source .env
    MISSING_VARS=""
    
    # List of critical variables
    CRITICAL_VARS=(
        "AWS_REGION"
        "PROJECT_PREFIX"
        "ENVIRONMENT"
        "SQS_QUEUE_NAME"
        "SQS_DLQ_NAME"
        "LAMBDA_FUNCTION_NAME"
        "FAST_API_ECR_REPOSITORY_URI"
    )
    
    for var in "${CRITICAL_VARS[@]}"; do
        if [ -z "${!var}" ]; then
            MISSING_VARS="$MISSING_VARS $var"
        fi
    done
    
    if [ -z "$MISSING_VARS" ]; then
        echo -e "  ✅ All critical variables are set"
    else
        echo -e "  ❌ Missing variables:$MISSING_VARS"
        ERRORS=$((ERRORS + 1))
    fi
fi

# Check AWS CLI
echo -e "${GREEN}[CHECK 3]${NC} AWS CLI configuration..."
if aws sts get-caller-identity &>/dev/null; then
    echo -e "  ✅ AWS CLI is configured"
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo -e "  Account: $ACCOUNT_ID"
else
    echo -e "  ❌ AWS CLI not configured or no credentials"
    echo -e "  ${YELLOW}Run: aws configure${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check Docker
echo -e "${GREEN}[CHECK 4]${NC} Docker installation..."
if command -v docker &>/dev/null; then
    echo -e "  ✅ Docker is installed"
    if docker ps &>/dev/null; then
        echo -e "  ✅ Docker daemon is running"
    else
        echo -e "  ❌ Docker daemon is not running"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "  ❌ Docker is not installed"
    ERRORS=$((ERRORS + 1))
fi

# Check script permissions
echo -e "${GREEN}[CHECK 5]${NC} Script permissions..."
NON_EXEC=""
for script in scripts/step-*.sh; do
    if [ ! -x "$script" ]; then
        NON_EXEC="$NON_EXEC $(basename $script)"
    fi
done

if [ -z "$NON_EXEC" ]; then
    echo -e "  ✅ All scripts are executable"
else
    echo -e "  ⚠️  Non-executable scripts found"
    echo -e "  ${YELLOW}Run: chmod +x scripts/*.sh${NC}"
    WARNINGS=$((WARNINGS + 1))
fi

# Check Python requirements
echo -e "${GREEN}[CHECK 6]${NC} Python dependencies..."
if command -v python3 &>/dev/null; then
    echo -e "  ✅ Python3 is installed"
else
    echo -e "  ❌ Python3 is not installed"
    ERRORS=$((ERRORS + 1))
fi

# Check key files exist
echo -e "${GREEN}[CHECK 7]${NC} Key project files..."
KEY_FILES=(
    "scripts/error-handling.sh"
    "scripts/step-navigation.sh"
    "scripts/step-000-setup-configuration.sh"
    "lambdas/transcription-router/lambda_function.py"
    "docker/Dockerfile"
)

for file in "${KEY_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -e "  ✅ $file exists"
    else
        echo -e "  ❌ $file missing"
        ERRORS=$((ERRORS + 1))
    fi
done

# Summary
echo
echo -e "${BLUE}======================================${NC}"
if [ $ERRORS -eq 0 ]; then
    if [ $WARNINGS -eq 0 ]; then
        echo -e "${GREEN}✅ All checks passed!${NC}"
        echo -e "${GREEN}Ready to run from step-000${NC}"
    else
        echo -e "${YELLOW}⚠️  Setup complete with $WARNINGS warnings${NC}"
        echo -e "${YELLOW}Address warnings above for best results${NC}"
    fi
else
    echo -e "${RED}❌ Found $ERRORS errors${NC}"
    echo -e "${RED}Fix errors above before proceeding${NC}"
    exit 1
fi
echo -e "${BLUE}======================================${NC}"

# Suggest next steps
echo
echo -e "${GREEN}[NEXT STEPS]${NC}"
echo "1. If starting fresh:"
echo "   ./scripts/step-000-setup-configuration.sh"
echo
echo "2. If resuming after GPU instance launch:"
echo "   ./scripts/step-326-fast-api-check-gpu-health.sh"
echo "   ./scripts/step-330-fast-api-test-transcription.sh"
echo
echo "3. To deploy Lambda and complete setup:"
echo "   ./scripts/step-340-deploy-lambda-router.sh"
echo "   ./scripts/step-341-configure-eventbridge-trigger.sh"
echo "   ./scripts/step-342-test-lambda-router.sh"