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

# Show LOCAL and ECR status with clear separation
echo -e "\n${GREEN}[STEP 4]${NC} Docker Image Status - LOCAL vs ECR"
echo -e "${YELLOW}=================================================${NC}"

echo -e "\n📱 ${BLUE}LOCAL DOCKER IMAGES${NC} (on this machine):"
echo -e "${YELLOW}┌─────────────────────────────────────────────────────────────────────────────┐${NC}"
echo -e "${YELLOW}│ Repository                    │ Tag                │ Size    │ Created       │${NC}"
echo -e "${YELLOW}├─────────────────────────────────────────────────────────────────────────────┤${NC}"
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}" | grep -E "fast-api-gpu|$FAST_API_ECR_REPO_NAME" | head -5 | while IFS=$'\t' read -r repo tag size created; do
    if [[ ${#repo} -gt 30 ]]; then
        repo="$(echo "$repo" | cut -c1-27)..."
    fi
    printf "${YELLOW}│${NC} %-30s ${YELLOW}│${NC} %-18s ${YELLOW}│${NC} %-7s ${YELLOW}│${NC} %-13s ${YELLOW}│${NC}\n" "$repo" "$tag" "$size" "$created"
done 2>/dev/null || {
    echo -e "${YELLOW}│${NC} fast-api-gpu                   ${YELLOW}│${NC} $VERSION_TAG      ${YELLOW}│${NC} ~10GB   ${YELLOW}│${NC} just now      ${YELLOW}│${NC}"
}
echo -e "${YELLOW}└─────────────────────────────────────────────────────────────────────────────┘${NC}"

echo -e "\n☁️  ${BLUE}ECR REPOSITORY STATUS${NC} (AWS Cloud):"
echo -e "${YELLOW}┌─────────────────────────────────────────────────────────────────────────────┐${NC}"
echo -e "${YELLOW}│ Repository: $FAST_API_ECR_REPO_NAME${NC}"
echo -e "${YELLOW}│ Region: $AWS_REGION${NC}"

# Check if any images exist in ECR
ECR_IMAGE_COUNT=$(aws ecr list-images --repository-name "$FAST_API_ECR_REPO_NAME" --region "$AWS_REGION" --query 'length(imageIds)' --output text 2>/dev/null || echo "0")

if [ "$ECR_IMAGE_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC} ❌ ${RED}REPOSITORY IS EMPTY${NC} - No images pushed yet"
    echo -e "${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC} 💡 ${BLUE}To push images to ECR:${NC}"
    echo -e "${YELLOW}│${NC}    ./scripts/step-313-fast-api-push-s3-image.sh"
else
    echo -e "${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC} ✅ ${GREEN}$ECR_IMAGE_COUNT images found:${NC}"
    aws ecr list-images --repository-name "$FAST_API_ECR_REPO_NAME" --region "$AWS_REGION" --query 'imageIds[*].imageTag' --output text 2>/dev/null | tr '\t' '\n' | head -3 | while read -r tag; do
        echo -e "${YELLOW}│${NC}    • $tag"
    done
fi
echo -e "${YELLOW}└─────────────────────────────────────────────────────────────────────────────┘${NC}"

echo -e "\n${BLUE}📋 WHAT THIS MEANS:${NC}"
echo -e "• ${GREEN}LOCAL${NC}: Images built and stored on this machine (ready for testing)"
echo -e "• ${BLUE}ECR${NC}: Images pushed to AWS (ready for deployment to EC2/ECS)"
echo -e "• ${YELLOW}Size${NC}: ~10GB each (includes CUDA, PyTorch, Whisper models)"

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

echo -e "${GREEN}[✅ IMAGES CREATED LOCALLY]${NC}"
echo -e "📱 Local: ${BLUE}fast-api-gpu:$VERSION_TAG${NC}"
echo -e "🏷️  ECR-tagged: ${BLUE}$FAST_API_ECR_REPOSITORY_URI:$VERSION_TAG${NC}"
echo

echo -e "${YELLOW}[⚠️  IMPORTANT - IMAGES ARE LOCAL ONLY]${NC}"
echo -e "• Images exist on THIS MACHINE only"
echo -e "• NOT yet visible in AWS ECR Console" 
echo -e "• NOT yet deployable to EC2/ECS instances"
echo

echo -e "${GREEN}[📝 CONFIGURATION UPDATED]${NC}"
echo -e "Updated .env with: ${BLUE}FAST_API_DOCKER_IMAGE_TAG=$VERSION_TAG${NC}"
echo

echo -e "${GREEN}[🚀 NEW S3-ENHANCED FEATURES]${NC}"
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
