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

log_info "Pushing s3-enhanced tag..." "$SCRIPT_NAME"
if ! docker push $FAST_API_ECR_REPOSITORY_URI:s3-enhanced; then
    log_error "Failed to push s3-enhanced image" "$SCRIPT_NAME"
    exit 1
fi

log_info "Pushing latest-s3 tag..." "$SCRIPT_NAME"
if ! docker push $FAST_API_ECR_REPOSITORY_URI:latest-s3; then
    log_error "Failed to push latest-s3 image" "$SCRIPT_NAME"
    exit 1
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
echo -e "${GREEN}[AVAILABLE TAGS]${NC}"
echo "• s3-enhanced - Main S3-enabled version"
echo "• latest-s3 - Alias for s3-enhanced"
echo "• fixed - Previous NumPy fix (no S3)"
echo "• latest - Original version"
echo
echo -e "${GREEN}[DEPLOYMENT OPTIONS]${NC}"
echo "1. Deploy new instance with S3 support:"
echo "   ./scripts/step-300-fast-api-smart-deploy.sh --tag=s3-enhanced"
echo
echo "2. Update existing instance (manual):"
echo "   ssh into instance and pull new image"
echo
echo -e "${GREEN}[S3 API USAGE - 3 Endpoints Available]${NC}"
echo ""
echo "1. S3 to S3 transcription (s3:// URIs):"
echo 'curl -X POST http://your-api:8000/transcribe-s3 \'
echo '  -H "Content-Type: application/json" \'
echo '  -d '"'"'{"s3_input_path": "s3://bucket/audio.mp3",
       "s3_output_path": "s3://bucket/transcript.json",
       "return_text": false}'"'"
echo ""
echo "2. URL transcription (http/https URLs):"
echo 'curl -X POST http://your-api:8000/transcribe-url \'
echo '  -H "Content-Type: application/json" \'
echo '  -d '"'"'{"audio_url": "https://example.com/audio.mp3"}'"'"
echo ""
echo "3. File upload (original functionality):"
echo 'curl -X POST -F '"'"'file=@audio.mp3'"'"' http://your-api:8000/transcribe'
# Mark step as completed
create_checkpoint "$SCRIPT_NAME" "completed" "$SCRIPT_NAME"
log_success "S3-Enhanced images pushed to ECR successfully" "$SCRIPT_NAME"

# Show next step using navigation library
if declare -f show_next_step > /dev/null 2>&1; then
    show_next_step "$0" "$(dirname "$0")"
else
    echo ""
    log_info "Next step: Run ./scripts/step-320-fast-api-launch-gpu-instances.sh" "$SCRIPT_NAME"
fi
