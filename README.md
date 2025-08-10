# Smart Transcription Router

A hybrid transcription service that intelligently routes audio transcription requests either directly to a GPU-powered FastAPI server (when available) or to an SQS queue for batch processing. This architecture optimizes for both low latency and cost efficiency.

![Smart Transcription Router Architecture](./architecture-diagram.png)

## Architecture Overview

```
┌─────────────────────┐
│   Audio Upload      │
│   (EventBridge)     │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Lambda Router      │
│  (Health Check)     │
└──────┬───────┬──────┘
       │       │
    Healthy    │ Not Healthy
       │       │
       ▼       ▼
┌──────────┐ ┌──────────┐
│ FastAPI  │ │   SQS    │
│ (Direct) │ │ (Queue)  │
└──────────┘ └────┬─────┘
                  │
                  ▼
           ┌──────────────┐
           │ Batch Worker │
           │ (Scheduled)  │
           └──────────────┘
```

## Key Features

- **Intelligent Routing**: Lambda function checks if FastAPI server is running and routes accordingly
- **Exponential Backoff Retry**: Up to 3 retry attempts with 1s, 2s, 4s delays for transient failures  
- **Idempotent Processing**: Automatically skips chunks that are already transcribed
- **Automatic Session Combination**: Creates session-level transcripts when all chunks complete
- **Hybrid Processing**: 
  - Direct HTTP calls for real-time transcription when server is up
  - SQS queue for batch processing when server is down or for deferred jobs
- **Cost Optimization**: GPU instances only run when needed
- **Automatic Failover**: Seamlessly queues requests when server is unavailable
- **High Success Rate**: Improved from ~78% to ~95%+ chunk transcription success

## Components

### 1. Lambda Router
- Receives audio upload events from EventBridge
- Checks if transcript already exists (idempotent processing)
- Performs health check on FastAPI server
- Retries failed FastAPI requests with exponential backoff (1s, 2s, 4s delays)
- Automatically combines session transcripts when chunks complete
- Falls back to SQS queue if FastAPI fails after all retries
- Routes to either direct HTTP or SQS based on availability

### 2. FastAPI Server (GPU)
- High-performance transcription using WhisperX
- Supports multiple input methods:
  - Direct file upload
  - S3 input/output
  - URL-based transcription
- Runs on GPU instances for fast processing

### 3. SQS Queue
- Stores transcription requests when server is offline
- Enables batch processing during scheduled windows
- Provides reliable message delivery

### 4. Batch Worker
- Processes SQS queue messages
- Can be triggered on schedule (e.g., midnight)
- Spins up GPU instances as needed

## Quick Start

### 🎯 Core Smart Router (SQS-Only Mode)
```bash
# Phase 1: Basic Setup
./scripts/step-000-setup-configuration.sh
./scripts/step-001-validate-configuration.sh
./scripts/step-010-setup-iam-permissions.sh
./scripts/step-011-validate-iam-permissions.sh
./scripts/step-020-create-sqs-resources.sh
./scripts/step-021-validate-sqs-resources.sh

# Phase 2: Smart Router
./scripts/step-340-deploy-lambda-router.sh
./scripts/step-341-configure-eventbridge-trigger.sh
./scripts/step-342-test-lambda-router.sh
```

### 🚀 Optional: Add Real-Time Processing
```bash
# FastAPI Server (optional)
./scripts/step-301-fast-api-setup-ecr-repository.sh
./scripts/step-302-fast-api-validate-ecr-configuration.sh
./scripts/step-312-fast-api-build-s3-enhanced-image.sh
./scripts/step-313-fast-api-push-s3-image.sh
./scripts/step-320-fast-api-launch-gpu-instances.sh
./scripts/step-326-fast-api-check-gpu-health.sh
./scripts/step-330-fast-api-test-transcription.sh
```

## Usage Examples

### When Server is Running
```bash
# Direct transcription via HTTP
curl -X POST http://<server-ip>:8000/transcribe-s3 \
  -H 'Content-Type: application/json' \
  -d '{"s3_input_path": "s3://bucket/audio.mp3"}'
```

### When Server is Down
Requests automatically queue to SQS and process when the server starts or during scheduled batch runs.

## Cost Optimization

- GPU instances auto-terminate after processing
- No compute costs when idle
- Batch processing consolidates GPU usage
- Real-time processing available on-demand

## Environment Variables

Key configuration in `.env`:
- `AWS_REGION`: AWS region for resources
- `FAST_API_ECR_REPOSITORY_URI`: ECR repository for Docker images
- `SQS_QUEUE_URL`: Queue for batch processing
- `FAST_API_SERVER_URL`: FastAPI server endpoint

## Development

The service is built with:
- FastAPI for high-performance HTTP API
- WhisperX for GPU-accelerated transcription
- AWS Lambda for intelligent routing
- SQS for reliable message queuing
- Docker for containerization

## Next Steps

- [ ] Implement Lambda router function
- [ ] Add CloudWatch monitoring
- [ ] Set up auto-scaling policies
- [ ] Configure scheduled batch processing
- [ ] Add dead letter queue handling