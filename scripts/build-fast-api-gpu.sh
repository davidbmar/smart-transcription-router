#!/bin/bash
# Fast API GPU Image Build Script
set -e

source .env
echo "🚀 Building Fast API GPU Docker image..."
echo "Repository: $FAST_API_ECR_REPOSITORY_URI"

cd "$(dirname "$0")/.."

# Build image with Fast API GPU tag
docker build \
    -f docker/fast-api/Dockerfile \
    -t "$FAST_API_ECR_REPO_NAME:$FAST_API_DOCKER_IMAGE_TAG" \
    -t "$FAST_API_ECR_REPOSITORY_URI:$FAST_API_DOCKER_IMAGE_TAG" \
    docker/fast-api/

echo "✅ Fast API Docker image built successfully"
echo "Local tag: $FAST_API_ECR_REPO_NAME:$FAST_API_DOCKER_IMAGE_TAG"
echo "ECR tag: $FAST_API_ECR_REPOSITORY_URI:$FAST_API_DOCKER_IMAGE_TAG"
