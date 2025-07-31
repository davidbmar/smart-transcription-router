# Essential vs Optional Scripts Analysis

## ✅ ESSENTIAL SCRIPTS (Core Functionality)

### Phase 1: Basic Setup (Required)
- `step-000-setup-configuration.sh` - ✅ **ESSENTIAL** - Creates .env file
- `step-001-validate-configuration.sh` - ✅ **ESSENTIAL** - Validates AWS setup
- `step-010-setup-iam-permissions.sh` - ✅ **ESSENTIAL** - Creates IAM roles
- `step-011-validate-iam-permissions.sh` - ✅ **ESSENTIAL** - Validates permissions
- `step-020-create-sqs-resources.sh` - ✅ **ESSENTIAL** - Creates SQS queues
- `step-021-validate-sqs-resources.sh` - ✅ **ESSENTIAL** - Validates SQS

### Phase 3: Smart Router (Core Feature)
- `step-340-deploy-lambda-router.sh` - ✅ **ESSENTIAL** - Deploys smart router
- `step-341-configure-eventbridge-trigger.sh` - ✅ **ESSENTIAL** - EventBridge setup
- `step-342-test-lambda-router.sh` - ✅ **ESSENTIAL** - Tests router

### Cleanup
- `step-999-destroy-all-resources-complete-teardown.sh` - ✅ **ESSENTIAL** - Cleanup

## ⚠️ OPTIONAL SCRIPTS (FastAPI Server)

### Phase 2: FastAPI Deployment (Optional - only if you want real-time processing)
- `step-301-fast-api-setup-ecr-repository.sh` - Optional - ECR for Docker images
- `step-302-fast-api-validate-ecr-configuration.sh` - Optional - ECR validation
- `step-310-fast-api-build-gpu-docker-image.sh` - Optional - Build basic image
- `step-311-fast-api-push-image-to-ecr.sh` - Optional - Push basic image
- `step-312-fast-api-build-s3-enhanced-image.sh` - Optional - Build S3 image
- `step-313-fast-api-push-s3-image.sh` - Optional - Push S3 image
- `step-320-fast-api-launch-gpu-instances.sh` - Optional - Launch GPU instances
- `step-326-fast-api-check-gpu-health.sh` - Optional - Health checks
- `step-330-fast-api-test-transcription.sh` - Optional - Test FastAPI

## ❌ NOT NEEDED (Can be removed)

### Unused/Redundant Scripts
- `step-005-setup-vad-model.sh` - ❌ **NOT NEEDED** - VAD not used in current architecture
- `step-041-test-complete-workflow.sh` - ❌ **NOT NEEDED** - Redundant testing
- `step-060-choose-deployment-path.sh` - ❌ **NOT NEEDED** - Path is fixed (3xx)
- `step-300-fast-api-smart-deploy.sh` - ❌ **NOT NEEDED** - Automation script not needed
- `step-300-scripts-for-fast-api-transcription.sh` - ❌ **NOT NEEDED** - Documentation only
- `step-325-fast-api-fix-ssh-access.sh` - ❌ **NOT NEEDED** - Troubleshooting only
- `step-327-fast-api-fix-iam-and-restart.sh` - ❌ **NOT NEEDED** - Troubleshooting only
- `step-999-terminate-workers-or-selective-cleanup.sh` - ❌ **NOT NEEDED** - Partial cleanup

## 📋 MINIMAL DEPLOYMENT (SQS-only mode)

For a minimal smart router that only uses SQS queues (no FastAPI server):

```bash
# Essential scripts only (10 scripts)
./scripts/step-000-setup-configuration.sh
./scripts/step-001-validate-configuration.sh
./scripts/step-010-setup-iam-permissions.sh
./scripts/step-011-validate-iam-permissions.sh
./scripts/step-020-create-sqs-resources.sh
./scripts/step-021-validate-sqs-resources.sh
./scripts/step-340-deploy-lambda-router.sh
./scripts/step-341-configure-eventbridge-trigger.sh
./scripts/step-342-test-lambda-router.sh

# Cleanup when done
./scripts/step-999-destroy-all-resources-complete-teardown.sh
```

## 📋 FULL DEPLOYMENT (Hybrid mode)

For the complete hybrid system with both FastAPI and SQS:

```bash
# All essential scripts + FastAPI scripts (19 scripts)
# Phase 1: Basic Setup
./scripts/step-000-setup-configuration.sh
./scripts/step-001-validate-configuration.sh
./scripts/step-010-setup-iam-permissions.sh
./scripts/step-011-validate-iam-permissions.sh
./scripts/step-020-create-sqs-resources.sh
./scripts/step-021-validate-sqs-resources.sh

# Phase 2: FastAPI (optional)
./scripts/step-301-fast-api-setup-ecr-repository.sh
./scripts/step-302-fast-api-validate-ecr-configuration.sh
./scripts/step-312-fast-api-build-s3-enhanced-image.sh  # Use S3 version
./scripts/step-313-fast-api-push-s3-image.sh
./scripts/step-320-fast-api-launch-gpu-instances.sh
./scripts/step-326-fast-api-check-gpu-health.sh
./scripts/step-330-fast-api-test-transcription.sh

# Phase 3: Smart Router
./scripts/step-340-deploy-lambda-router.sh
./scripts/step-341-configure-eventbridge-trigger.sh
./scripts/step-342-test-lambda-router.sh
```

## 🗑️ RECOMMENDED: Remove Unused Scripts

These scripts can be safely deleted to reduce confusion:

```bash
rm scripts/step-005-setup-vad-model.sh
rm scripts/step-041-test-complete-workflow.sh
rm scripts/step-060-choose-deployment-path.sh
rm scripts/step-300-fast-api-smart-deploy.sh
rm scripts/step-300-scripts-for-fast-api-transcription.sh
rm scripts/step-310-fast-api-build-gpu-docker-image.sh  # Keep only S3 version
rm scripts/step-311-fast-api-push-image-to-ecr.sh       # Keep only S3 version
rm scripts/step-325-fast-api-fix-ssh-access.sh
rm scripts/step-327-fast-api-fix-iam-and-restart.sh
rm scripts/step-999-terminate-workers-or-selective-cleanup.sh
```

This would reduce from 25 scripts to 15 essential scripts.