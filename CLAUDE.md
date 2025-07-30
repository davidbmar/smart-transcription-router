# CLAUDE.md - Smart Transcription Router Project Context

## Project Overview
This is a hybrid transcription service that intelligently routes audio transcription requests to either a GPU-powered FastAPI server (for real-time processing) or an SQS queue (for batch processing). The system optimizes for both low latency and cost efficiency.

## Architecture
- **Lambda Router**: Checks FastAPI server health and routes requests accordingly
- **FastAPI Server**: GPU-accelerated transcription using WhisperX (when available)
- **SQS Queue**: Reliable message queuing for batch processing (when server is down)
- **EventBridge Integration**: Receives audio upload events from cognito-lambda-s3-webserver-cloudfront

## Project History
This project was created by copying and organizing scripts from `transcription-sqs-spot-s3`, specifically:
- Step-0xx scripts (common setup and configuration)
- Step-3xx scripts (FastAPI deployment path)
- Added new step-34x scripts for Lambda router deployment and testing

## Key Components

### Scripts Organization
- `step-000` to `step-021`: Infrastructure setup (IAM, SQS, configuration)
- `step-300` to `step-330`: FastAPI server deployment and testing
- `step-340` to `step-342`: Lambda router deployment and EventBridge configuration

### Lambda Router (`lambdas/transcription-router/`)
- **Purpose**: Intelligent routing based on FastAPI server availability
- **Logic**: 
  - Check for running FastAPI instances with tag `fast-api-worker`
  - Perform health check on discovered servers
  - Route to FastAPI if available, otherwise queue to SQS
  - Support `force_batch` flag to always use SQS

### Docker Images
- `docker/fast-api/`: Contains both basic and S3-enhanced FastAPI servers
- Supports multiple endpoints: `/transcribe`, `/transcribe-s3`, `/transcribe-url`

## Environment Variables (.env)
Key variables saved by scripts:
- `AWS_REGION`: AWS region for resources
- `QUEUE_URL`: Main SQS queue URL (saved by step-020)
- `DLQ_URL`: Dead letter queue URL (saved by step-020)  
- `QUEUE_ARN`/`DLQ_ARN`: Queue ARNs (saved by step-020)
- `FAST_API_ECR_REPOSITORY_URI`: ECR repository URI (saved by step-301)
- `TRANSCRIPTION_ROUTER_LAMBDA_ARN`: Lambda function ARN (saved by step-340)
- `TRANSCRIPTION_ROUTER_FUNCTION_NAME`: Lambda function name (saved by step-340)
- `EVENT_BUS_NAME`: EventBridge bus name (user input in step-341)

## Current Status
✅ **Completed**:
- Project structure created with organized scripts
- Lambda router implemented with intelligent routing logic
- Deployment scripts for Lambda and EventBridge configuration
- Test scripts for validation
- Documentation with architecture diagrams

🔄 **Next Steps** (when resuming):
1. **CORE DEPLOYMENT (9 scripts)**: Run step-000 and follow next-step prompts:
   - Phase 1: step-000 → step-001 → step-010 → step-011 → step-020 → step-021
   - Phase 2: step-340 → step-341 → step-342
2. **OPTIONAL FASTAPI (7 scripts)**: Add real-time processing if needed:
   - step-301 → step-302 → step-312 → step-313 → step-320 → step-326 → step-330
3. Test end-to-end flow with audio uploads
4. Implement midnight batch processor

✅ **Updated**: All scripts now automatically show next step with descriptions
✅ **Streamlined**: Reduced from 25 to 17 essential scripts
✅ **Fixed**: Variable name mismatch - Lambda correctly uses QUEUE_URL from .env

## Related Repositories
- `cognito-lambda-s3-webserver-cloudfront`: Audio upload source (publishes to EventBridge)
- `eventbridge-orchestrator`: Event bus infrastructure
- `transcription-sqs-spot-s3`: Original transcription service (source for this project)

## Testing Commands
```bash
# Deploy Lambda router
./scripts/step-340-deploy-lambda-router.sh

# Configure EventBridge trigger
./scripts/step-341-configure-eventbridge-trigger.sh

# Test Lambda functionality
./scripts/step-342-test-lambda-router.sh

# Test FastAPI server
./scripts/step-330-fast-api-test-transcription.sh
```

## File Locations
- Lambda code: `lambdas/transcription-router/index.py`
- FastAPI servers: `docker/fast-api/fast_api_server.py` and `fast_api_server_s3.py`
- Architecture diagram: `architecture-diagram.txt`
- Main documentation: `README.md`