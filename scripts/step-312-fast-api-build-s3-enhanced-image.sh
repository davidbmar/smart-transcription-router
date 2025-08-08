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
echo
echo -e "${GREEN}[INFO]${NC} This builds the Fast API image with S3 support"
echo -e "${GREEN}[INFO]${NC} New features:"
echo "  • Direct S3 input/output support"
echo "  • URL-based transcription"
echo "  • Backward compatible with file uploads"
echo

# Verify Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} Docker is not installed"
    exit 1
fi

# Generate timestamp-based version tag
TIMESTAMP=$(date +"%Y.%m.%d.%H%M")
VERSION_TAG="${TIMESTAMP}-s3"

echo -e "${GREEN}[STEP 1]${NC} Generating version tag..."
echo "New version tag: $VERSION_TAG"

# Check if this tag already exists in ECR to avoid conflicts
echo -e "${GREEN}[STEP 2]${NC} Checking ECR for existing tags..."
EXISTING_TAGS=$(aws ecr describe-images \
    --repository-name "$FAST_API_ECR_REPO_NAME" \
    --region "$AWS_REGION" \
    --query 'imageDetails[*].imageTags[*]' \
    --output text 2>/dev/null | tr '\t' '\n' | sort -rV | head -10)

if echo "$EXISTING_TAGS" | grep -q "^$VERSION_TAG$"; then
    echo -e "${YELLOW}[WARNING]${NC} Tag $VERSION_TAG already exists, adding suffix..."
    VERSION_TAG="${TIMESTAMP}-s3-$(date +%s | tail -c 3)"
fi

echo "Using version tag: $VERSION_TAG"

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

# Update .env file with new image tag
echo -e "\n${GREEN}[STEP 5]${NC} Updating .env with new image tag..."
if [ -f ".env" ]; then
    # Update FAST_API_DOCKER_IMAGE_TAG in .env file
    if grep -q "FAST_API_DOCKER_IMAGE_TAG=" .env; then
        sed -i "s/FAST_API_DOCKER_IMAGE_TAG=.*/FAST_API_DOCKER_IMAGE_TAG=\"$VERSION_TAG\"/" .env
    else
        echo "export FAST_API_DOCKER_IMAGE_TAG=\"$VERSION_TAG\"" >> .env
    fi
    echo "Updated FAST_API_DOCKER_IMAGE_TAG=$VERSION_TAG in .env"
else
    echo -e "${RED}[ERROR]${NC} .env file not found!"
    exit 1
fi

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
