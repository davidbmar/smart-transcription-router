#!/bin/bash
# Fast API ECR Login Helper Script
set -e

source .env
echo "🔐 Logging into ECR for Fast API..."
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$FAST_API_ECR_REPOSITORY_URI"
echo "✅ Fast API ECR login successful"
