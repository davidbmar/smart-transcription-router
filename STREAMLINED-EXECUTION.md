# Streamlined Smart Transcription Router - Execution Guide

## 🎯 CORE WORKFLOW (9 Scripts - Recommended Start)

### Phase 1: Basic Setup (6 scripts)
```bash
./scripts/step-000-setup-configuration.sh      # Configure environment & AWS
./scripts/step-001-validate-configuration.sh   # Validate AWS connectivity
./scripts/step-010-setup-iam-permissions.sh    # Create IAM roles & policies
./scripts/step-011-validate-iam-permissions.sh # Verify IAM setup
./scripts/step-020-create-sqs-resources.sh     # Create SQS queues & S3 bucket
./scripts/step-021-validate-sqs-resources.sh   # Test SQS functionality
```

### Phase 2: Smart Router (3 scripts)
```bash
./scripts/step-340-deploy-lambda-router.sh     # Deploy intelligent router Lambda
./scripts/step-341-configure-eventbridge-trigger.sh # Connect to EventBridge
./scripts/step-342-test-lambda-router.sh       # Test routing logic
```

**Result**: Complete smart router that queues all audio for batch processing!

## 🚀 OPTIONAL: Add Real-Time Processing (7 additional scripts)

**Only add these if you want immediate transcription when FastAPI server is running:**

```bash
./scripts/step-301-fast-api-setup-ecr-repository.sh # Create ECR repository
./scripts/step-302-fast-api-validate-ecr-configuration.sh # Validate ECR
./scripts/step-312-fast-api-build-s3-enhanced-image.sh # Build Docker image
./scripts/step-313-fast-api-push-s3-image.sh       # Push to ECR
./scripts/step-320-fast-api-launch-gpu-instances.sh # Launch GPU instances
./scripts/step-326-fast-api-check-gpu-health.sh    # Verify health
./scripts/step-330-fast-api-test-transcription.sh  # Test FastAPI
```

**Result**: Hybrid system that routes to FastAPI when available, SQS when not!

## 🗑️ Cleanup
```bash
./scripts/step-999-destroy-all-resources-complete-teardown.sh # Complete teardown
```

## 📊 TOTAL SCRIPTS: 17 (down from 25)

**Removed unnecessary scripts:**
- ❌ step-005-setup-vad-model.sh (VAD not needed)
- ❌ step-041-test-complete-workflow.sh (redundant testing)
- ❌ step-060-choose-deployment-path.sh (path is fixed)
- ❌ step-300-* (automation helpers not needed)
- ❌ step-310/311 (basic FastAPI - use S3 version instead)
- ❌ step-325/327 (troubleshooting scripts)
- ❌ step-999-terminate-* (partial cleanup not needed)

**Kept essential scripts only** for clear, focused deployment paths!