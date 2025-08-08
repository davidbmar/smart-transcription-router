#!/bin/bash

# step-313-fast-api-push-s3-image.sh - Push S3-enhanced Fast API image to ECR
# This script pushes the S3-enhanced Docker image to ECR repository
# Prerequisites: step-312 (build S3-enhanced image)
# Outputs: Docker images pushed to ECR with s3-enhanced and latest-s3 tags

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
SCRIPT_NAME="step-313-fast-api-push-s3-image"
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
echo -e "${BLUE}📤 Push S3-Enhanced Fast API to ECR${NC}"
echo -e "${BLUE}======================================${NC}"

echo -e "${GREEN}[VERSIONING STRATEGY]${NC} This script demonstrates best practices:"
echo "  • Reads pinned version from .env (set by step-312)"
echo "  • Pushes exact versioned tag to ECR"
echo "  • Creates 'stable-s3' alias for tested versions"
echo "  • NEVER relies on floating 'latest' tags"
echo
echo -e "${CYAN}[WHY THIS MATTERS]${NC}"
echo "  • Pinned versions ensure reproducible deployments"
echo "  • Date-based tags make rollbacks traceable"
echo "  • Eliminates 'works on my machine' deployment issues"
echo

# Validate prerequisites
if ! docker images | grep -q "$FAST_API_ECR_REPOSITORY_URI.*s3-enhanced" 2>/dev/null; then
    log_error "S3-enhanced image not found locally" "$SCRIPT_NAME"
    echo -e "${YELLOW}💡 Run: ./scripts/step-312-fast-api-build-s3-enhanced-image.sh${NC}"
    exit 1
fi

# Login to ECR
log_info "Logging into ECR..." "$SCRIPT_NAME"
if ! aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $FAST_API_ECR_REPOSITORY_URI; then
    log_error "Failed to login to ECR" "$SCRIPT_NAME"
    exit 1
fi
log_success "ECR login successful" "$SCRIPT_NAME"

# Verify images exist locally (already done in prerequisites)

# Push images
log_info "Pushing images to ECR..." "$SCRIPT_NAME"

# Read the pinned version from .env (best practice)
log_info "Reading pinned image version from .env..." "$SCRIPT_NAME"
IMAGE_TAG="$FAST_API_DOCKER_IMAGE_TAG"

if [ -z "$IMAGE_TAG" ]; then
    log_error "No FAST_API_DOCKER_IMAGE_TAG configured in .env file" "$SCRIPT_NAME"
    echo -e "${YELLOW}[REQUIRED]${NC} Run step-312 first to build and pin a version:"
    echo "  ./scripts/step-312-fast-api-build-s3-enhanced-image.sh"
    echo -e "${CYAN}[WHY]${NC} We never deploy without an explicit version pin"
    exit 1
fi

echo -e "${CYAN}[PINNED VERSION]${NC} Using version from .env: $IMAGE_TAG"
echo -e "${CYAN}[BEST PRACTICE]${NC} This ensures consistent deployments across environments"
log_info "Pushing versioned image with tag: $IMAGE_TAG" "$SCRIPT_NAME"
if ! docker push $FAST_API_ECR_REPOSITORY_URI:$IMAGE_TAG; then
    log_error "Failed to push image with tag $IMAGE_TAG" "$SCRIPT_NAME"
    exit 1
fi

# Create a 'stable-s3' alias (avoiding 'latest' anti-pattern)
echo -e "${CYAN}[CREATING ALIAS]${NC} stable-s3 -> $IMAGE_TAG"
echo -e "${CYAN}[WHEN TO USE]${NC} stable-s3 alias for tested versions in development"
echo -e "${CYAN}[PRODUCTION]${NC} Always use exact version tags: $IMAGE_TAG"
log_info "Creating stable-s3 alias..." "$SCRIPT_NAME"

if ! docker tag $FAST_API_ECR_REPOSITORY_URI:$IMAGE_TAG $FAST_API_ECR_REPOSITORY_URI:stable-s3; then
    log_warning "Failed to tag as stable-s3, continuing..." "$SCRIPT_NAME"
else
    if ! docker push $FAST_API_ECR_REPOSITORY_URI:stable-s3; then
        log_warning "Failed to push stable-s3 alias, continuing..." "$SCRIPT_NAME"
    else
        log_success "Alias created: stable-s3 points to $IMAGE_TAG" "$SCRIPT_NAME"
        echo -e "${YELLOW}[REMEMBER]${NC} Use specific version tags in production!"
    fi
fi

log_success "All images pushed successfully" "$SCRIPT_NAME"

# Verify push succeeded
log_info "Verifying images in ECR..." "$SCRIPT_NAME"
if aws ecr describe-images \
    --repository-name "$FAST_API_ECR_REPO_NAME" \
    --region "$AWS_REGION" \
    --query 'imageDetails[?contains(imageTags, `s3-enhanced`) || contains(imageTags, `latest-s3`)].[imageTags[0],imagePushedAt,imageSizeInBytes]' \
    --output table; then
    log_success "Images verified in ECR" "$SCRIPT_NAME"
else
    log_warning "Could not verify images, but push may have succeeded" "$SCRIPT_NAME"
fi

echo
echo -e "${BLUE}======================================${NC}"
echo -e "${GREEN}✅ S3-Enhanced Images Pushed to ECR${NC}"
echo -e "${BLUE}======================================${NC}"
echo
echo -e "${GREEN}[PUSHED TAGS]${NC}"
echo "• $IMAGE_TAG - Specific version (PINNED in .env)"
echo "• stable-s3 - Alias pointing to $IMAGE_TAG"
echo
echo -e "${CYAN}[DEPLOYMENT STRATEGY]${NC}"
echo "✅ Production: Use exact version from .env: $IMAGE_TAG"
echo "⚠️  Development: Can use stable-s3 alias for testing"
echo "❌ Never: Use 'latest' tag in any environment"
echo
echo -e "${GREEN}[HOW TO FIND LATEST VERSION (if needed)]${NC}"
echo "📖 For reference only - always pin specific versions:"
echo "   find_latest_image_version \"$FAST_API_ECR_REPO_NAME\" \"$AWS_REGION\" \"-s3\""
echo "   # Copy the returned version to .env file"
echo "   # Never deploy with floating tags"
# Load next-step helper and show next step
if [ -f "$(dirname "$0")/next-step-helper.sh" ]; then
    source "$(dirname "$0")/next-step-helper.sh"
    show_next_step "$0" "$(dirname "$0")"
else
    echo ""
    log_info "Next step: Run ./scripts/step-320-fast-api-launch-gpu-instances.sh" "$SCRIPT_NAME"
fi
