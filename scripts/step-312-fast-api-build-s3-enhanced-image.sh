#!/bin/bash

# step-312-fast-api-build-s3-enhanced-image.sh - Build S3-enhanced Fast API Docker image

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the project root directory (parent of scripts directory)
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.env"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo -e "${RED}[ERROR]${NC} Configuration file not found at $CONFIG_FILE"
    exit 1
fi

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}🎤 Build S3-Enhanced Fast API Image${NC}"
echo -e "${BLUE}======================================${NC}"

# Explain our Docker versioning best practices
source "$(dirname "$0")/common-functions.sh"
explain_versioning_strategy

echo -e "${GREEN}[VERSIONING STRATEGY]${NC} This script will:"
echo "  • Generate unique timestamp-based tag (YYYY.MM.DD.HHMM-s3)"
echo "  • Check ECR for conflicts and resolve automatically"
echo "  • Update .env with the new version tag for deployment"
echo "  • Never rely on 'latest' tag for production reliability"
echo
echo -e "${GREEN}[S3-ENHANCED FEATURES]${NC} This image includes:"
echo "  • Direct S3 input/output support"
echo "  • URL-based transcription"
echo "  • Backward compatible with file uploads"
echo

# Verify Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} Docker is not installed"
    exit 1
fi

# Save project root directory before changing directories
PROJECT_ROOT="$(pwd)"

# Generate timestamp-based version tag using best practices
echo -e "${GREEN}[STEP 1]${NC} Generating date-based version tag..."
echo -e "${CYAN}[WHY]${NC} Date-based tags ensure immutable, traceable deployments"

VERSION_TAG=$(generate_version_tag "s3" "$FAST_API_ECR_REPO_NAME" "$AWS_REGION")

echo -e "${GREEN}[STEP 2]${NC} Version conflict resolution complete"
echo -e "${CYAN}[RESULT]${NC} Using version tag: $VERSION_TAG"
echo -e "${CYAN}[BENEFIT]${NC} This tag is unique, sortable, and traceable to build time"

# Change to Fast API directory
cd /home/ubuntu/transcription-sqs-spot-s3/docker/fast-api

echo -e "${GREEN}[STEP 3]${NC} Building S3-enhanced Docker image..."
echo "Repository: $FAST_API_ECR_REPOSITORY_URI"
echo "Tag: $VERSION_TAG"

# Build the image with versioned tag
docker build \
    --platform linux/amd64 \
    -t fast-api-gpu:$VERSION_TAG \
    -t $FAST_API_ECR_REPOSITORY_URI:$VERSION_TAG \
    .

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[OK]${NC} Docker image built successfully"
else
    echo -e "${RED}[ERROR]${NC} Docker build failed"
    exit 1
fi

# Show image details
echo -e "\n${GREEN}[STEP 4]${NC} Image details:"
docker images | grep -E "fast-api-gpu|$FAST_API_ECR_REPO_NAME" | head -5

# Update .env file with new image tag using best practices
echo -e "\n${GREEN}[STEP 5]${NC} Updating .env configuration with versioned tag..."
echo -e "${CYAN}[WHY]${NC} Pinning exact versions in .env ensures consistent deployments"
echo -e "${CYAN}[BEST PRACTICE]${NC} All downstream scripts will use this pinned version"

# Go back to project root to update .env file
cd "$PROJECT_ROOT"

if ! update_env_image_tag "FAST_API_DOCKER_IMAGE_TAG" "$VERSION_TAG"; then
    exit 1
fi

echo -e "${CYAN}[RESULT]${NC} Future deployments will use pinned version: $VERSION_TAG"

echo
echo -e "${BLUE}======================================${NC}"
echo -e "${GREEN}✅ S3-Enhanced Fast API Image Built${NC}"
echo -e "${BLUE}======================================${NC}"
echo
echo -e "${GREEN}[IMAGES CREATED]${NC}"
echo "Local: fast-api-gpu:$VERSION_TAG"
echo "ECR: $FAST_API_ECR_REPOSITORY_URI:$VERSION_TAG"
echo
echo -e "${GREEN}[CONFIGURATION UPDATED]${NC}"
echo "Updated .env with: FAST_API_DOCKER_IMAGE_TAG=$VERSION_TAG"
echo
echo -e "${GREEN}[NEW FEATURES]${NC}"
echo "• POST /transcribe-s3 - Direct S3 input/output"
echo "• POST /transcribe-url - Any URL (including presigned)"
echo "• POST /transcribe - Original file upload (unchanged)"
echo

# Load next-step helper and show next step
SCRIPT_DIR="$PROJECT_ROOT/scripts"
if [ -f "$SCRIPT_DIR/next-step-helper.sh" ]; then
    source "$SCRIPT_DIR/next-step-helper.sh"
    show_next_step "$0" "$SCRIPT_DIR"
fi
