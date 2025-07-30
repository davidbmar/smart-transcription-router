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

# Change to Fast API directory
cd /home/ubuntu/transcription-sqs-spot-s3/docker/fast-api

echo -e "${GREEN}[STEP 1]${NC} Building S3-enhanced Docker image..."
echo "Repository: $FAST_API_ECR_REPOSITORY_URI"
echo "Tag: s3-enhanced"

# Build the image with S3 support tag
docker build \
    --platform linux/amd64 \
    -t fast-api-gpu:s3-enhanced \
    -t $FAST_API_ECR_REPOSITORY_URI:s3-enhanced \
    .

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[OK]${NC} Docker image built successfully"
else
    echo -e "${RED}[ERROR]${NC} Docker build failed"
    exit 1
fi

# Show image details
echo -e "\n${GREEN}[STEP 2]${NC} Image details:"
docker images | grep -E "fast-api-gpu|$FAST_API_ECR_REPO_NAME" | head -5

# Tag as latest-s3 for clarity
docker tag fast-api-gpu:s3-enhanced $FAST_API_ECR_REPOSITORY_URI:latest-s3

echo
echo -e "${BLUE}======================================${NC}"
echo -e "${GREEN}✅ S3-Enhanced Fast API Image Built${NC}"
echo -e "${BLUE}======================================${NC}"
echo
echo -e "${GREEN}[IMAGES CREATED]${NC}"
echo "Local: fast-api-gpu:s3-enhanced"
echo "ECR: $FAST_API_ECR_REPOSITORY_URI:s3-enhanced"
echo "ECR: $FAST_API_ECR_REPOSITORY_URI:latest-s3"
echo
echo -e "${GREEN}[NEW FEATURES]${NC}"
echo "• POST /transcribe-s3 - Direct S3 input/output"
echo "• POST /transcribe-url - Any URL (including presigned)"
echo "• POST /transcribe - Original file upload (unchanged)"
echo

# Load next-step helper and show next step
if [ -f "$(dirname "$0")/next-step-helper.sh" ]; then
    source "$(dirname "$0")/next-step-helper.sh"
    show_next_step "$0" "$(dirname "$0")"
fi
