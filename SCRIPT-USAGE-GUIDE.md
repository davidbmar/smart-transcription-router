# Smart Transcription Router - Script Usage Guide

## 🎯 CORE WORKFLOWS

### Workflow 1: SQS-Only Mode (Batch Processing Only)
**Use Case**: Cost-effective batch processing, no real-time needs
**Scripts**: 10 essential scripts
```bash
# Basic setup (required)
./scripts/step-000-setup-configuration.sh      # Configure environment
./scripts/step-001-validate-configuration.sh   # Validate AWS setup
./scripts/step-010-setup-iam-permissions.sh    # Create IAM roles
./scripts/step-011-validate-iam-permissions.sh # Validate permissions
./scripts/step-020-create-sqs-resources.sh     # Create SQS queues
./scripts/step-021-validate-sqs-resources.sh   # Test SQS

# Smart router (routes everything to SQS)
./scripts/step-340-deploy-lambda-router.sh     # Deploy router Lambda
./scripts/step-341-configure-eventbridge-trigger.sh # Setup EventBridge
./scripts/step-342-test-lambda-router.sh       # Test routing

# Test end-to-end
./scripts/step-041-test-complete-workflow.sh   # Optional: full test
```

### Workflow 2: Hybrid Mode (Real-time + Batch)
**Use Case**: Real-time transcription when possible, batch when not
**Scripts**: 15-18 scripts depending on options
```bash
# Phase 1: Basic setup (same as above)
./scripts/step-000-setup-configuration.sh
./scripts/step-001-validate-configuration.sh
./scripts/step-010-setup-iam-permissions.sh
./scripts/step-011-validate-iam-permissions.sh
./scripts/step-020-create-sqs-resources.sh
./scripts/step-021-validate-sqs-resources.sh

# Phase 2: FastAPI server setup
./scripts/step-301-fast-api-setup-ecr-repository.sh
./scripts/step-302-fast-api-validate-ecr-configuration.sh
./scripts/step-312-fast-api-build-s3-enhanced-image.sh  # Recommended: S3 version
./scripts/step-313-fast-api-push-s3-image.sh
./scripts/step-320-fast-api-launch-gpu-instances.sh
./scripts/step-326-fast-api-check-gpu-health.sh
./scripts/step-330-fast-api-test-transcription.sh

# Phase 3: Smart router (same as above)
./scripts/step-340-deploy-lambda-router.sh
./scripts/step-341-configure-eventbridge-trigger.sh
./scripts/step-342-test-lambda-router.sh
```

## 🔧 TROUBLESHOOTING SCRIPTS

### When FastAPI Server Issues Occur:
```bash
./scripts/step-325-fast-api-fix-ssh-access.sh    # Fix SSH connectivity
./scripts/step-327-fast-api-fix-iam-and-restart.sh # Fix IAM and restart
./scripts/step-326-fast-api-check-gpu-health.sh   # Check health status
```

### When You Need Guidance:
```bash
./scripts/step-060-choose-deployment-path.sh      # Interactive path selection
./scripts/step-300-scripts-for-fast-api-transcription.sh # FastAPI overview
```

## 🔄 ALTERNATIVE OPTIONS

### Option A: Basic FastAPI (No S3 integration)
Use `step-310` and `step-311` instead of `step-312` and `step-313`
```bash
./scripts/step-310-fast-api-build-gpu-docker-image.sh  # Basic image
./scripts/step-311-fast-api-push-image-to-ecr.sh       # Push basic
```

### Option B: VAD Model Setup (If needed by your FastAPI)
```bash
./scripts/step-005-setup-vad-model.sh  # Download VAD model
```

### Option C: Automated FastAPI Deployment
```bash
./scripts/step-300-fast-api-smart-deploy.sh  # Automates 301-330 sequence
```

## 🧪 TESTING & VALIDATION

### Individual Component Testing:
- `step-001` - AWS connectivity
- `step-011` - IAM permissions  
- `step-021` - SQS functionality
- `step-302` - ECR access
- `step-326` - GPU health
- `step-330` - FastAPI endpoints
- `step-342` - Router logic

### End-to-End Testing:
- `step-041` - Complete workflow test
- Manual testing with audio uploads from cognito-lambda-s3-webserver-cloudfront

## 🗑️ CLEANUP OPTIONS

### Selective Cleanup:
```bash
./scripts/step-999-terminate-workers-or-selective-cleanup.sh
```

### Complete Teardown:
```bash
./scripts/step-999-destroy-all-resources-complete-teardown.sh
```

## 📋 SCRIPT STATUS

**All scripts are kept** for maximum flexibility. Users can choose which workflow fits their needs:

- **Minimal users**: Use SQS-only workflow (10 scripts)
- **Full users**: Use hybrid workflow (15+ scripts)  
- **Troubleshooting**: Additional helper scripts available
- **Testing**: Multiple validation options

**No scripts removed** - just clear guidance on which ones to use for each scenario.