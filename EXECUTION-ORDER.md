# Smart Transcription Router - Script Execution Order

## Prerequisites
Make sure you have:
- AWS CLI configured with appropriate permissions
- Docker installed (for building images)
- Python 3.9+ installed (for Lambda deployment)

## Step-by-Step Execution Order

### Phase 1: Basic Setup (Required)
```bash
# 1. Initial configuration
./scripts/step-000-setup-configuration.sh
./scripts/step-001-validate-configuration.sh

# 2. IAM permissions setup
./scripts/step-010-setup-iam-permissions.sh
./scripts/step-011-validate-iam-permissions.sh

# 3. SQS queue creation
./scripts/step-020-create-sqs-resources.sh
./scripts/step-021-validate-sqs-resources.sh
```

### Phase 2: FastAPI Server Setup (Optional but Recommended)
```bash
# 4. ECR repository setup
./scripts/step-301-fast-api-setup-ecr-repository.sh
./scripts/step-302-fast-api-validate-ecr-configuration.sh

# 5. Docker image build and push
./scripts/step-310-fast-api-build-gpu-docker-image.sh  # or step-312 for S3 enhanced
./scripts/step-311-fast-api-push-image-to-ecr.sh      # or step-313 for S3 enhanced

# 6. Launch GPU instances
./scripts/step-320-fast-api-launch-gpu-instances.sh

# 7. Verify deployment
./scripts/step-326-fast-api-check-gpu-health.sh
./scripts/step-330-fast-api-test-transcription.sh
```

### Phase 3: Smart Router Setup (Core Feature)
```bash
# 8. Deploy Lambda router
./scripts/step-340-deploy-lambda-router.sh

# 9. Configure EventBridge integration
./scripts/step-341-configure-eventbridge-trigger.sh

# 10. Test the smart router
./scripts/step-342-test-lambda-router.sh
```

## Environment Variables Saved

### After step-020 (SQS Setup):
- `QUEUE_URL` - Main SQS queue URL
- `DLQ_URL` - Dead letter queue URL  
- `QUEUE_ARN` - Main queue ARN
- `DLQ_ARN` - Dead letter queue ARN

### After step-301 (ECR Setup):
- `FAST_API_ECR_REPOSITORY_URI` - ECR repository URI
- `FAST_API_ECR_REPO_NAME` - ECR repository name

### After step-340 (Lambda Router):
- `TRANSCRIPTION_ROUTER_LAMBDA_ARN` - Lambda function ARN
- `TRANSCRIPTION_ROUTER_FUNCTION_NAME` - Lambda function name

### After step-341 (EventBridge):
- `EVENT_BUS_NAME` - EventBridge bus name (user input)

## Skip Options

### Skip FastAPI Server (SQS-only mode):
If you only want batch processing, skip Phase 2:
```bash
# Phase 1: Basic Setup
./scripts/step-000-setup-configuration.sh
./scripts/step-001-validate-configuration.sh
./scripts/step-010-setup-iam-permissions.sh
./scripts/step-011-validate-iam-permissions.sh
./scripts/step-020-create-sqs-resources.sh
./scripts/step-021-validate-sqs-resources.sh

# Phase 3: Smart Router (will always route to SQS)
./scripts/step-340-deploy-lambda-router.sh
./scripts/step-341-configure-eventbridge-trigger.sh
./scripts/step-342-test-lambda-router.sh
```

### Skip Lambda Router (FastAPI-only mode):
If you only want direct HTTP processing:
```bash
# Phase 1: Basic Setup
./scripts/step-000-setup-configuration.sh
./scripts/step-001-validate-configuration.sh
./scripts/step-010-setup-iam-permissions.sh
./scripts/step-011-validate-iam-permissions.sh

# Phase 2: FastAPI Server Setup
./scripts/step-301-fast-api-setup-ecr-repository.sh
./scripts/step-302-fast-api-validate-ecr-configuration.sh
./scripts/step-310-fast-api-build-gpu-docker-image.sh
./scripts/step-311-fast-api-push-image-to-ecr.sh
./scripts/step-320-fast-api-launch-gpu-instances.sh
./scripts/step-330-fast-api-test-transcription.sh
```

## Cleanup
```bash
# Terminate workers and selective cleanup
./scripts/step-999-terminate-workers-or-selective-cleanup.sh

# Complete teardown (WARNING: Destroys everything)
./scripts/step-999-destroy-all-resources-complete-teardown.sh
```

## Troubleshooting

### Common Issues:
1. **Missing environment variables**: Run `source .env` before each phase
2. **IAM permission errors**: Ensure step-010 completed successfully
3. **Docker build fails**: Ensure Docker daemon is running
4. **Lambda deployment fails**: Check that SQS resources exist first

### Validation Commands:
```bash
# Check .env file
cat .env

# Verify AWS credentials
aws sts get-caller-identity

# Check SQS queue
aws sqs get-queue-attributes --queue-url "$QUEUE_URL" --attribute-names All

# Check Lambda function
aws lambda get-function --function-name "$TRANSCRIPTION_ROUTER_FUNCTION_NAME"
```