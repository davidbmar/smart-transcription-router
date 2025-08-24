# Step Scripts Overview

## GPU Worker Management (320s)

### step-321-gpu-worker-status.sh
**Show all GPU worker status (running/stopped/costs)**
- Displays running/stopped GPU workers in a table
- Shows real-time cost analysis (hourly/daily/monthly)
- Checks idle monitoring status on each worker
- Provides quick action suggestions

### step-322-gpu-worker-start-stopped.sh  
**Start existing stopped GPU workers**
- Lists all stopped GPU workers with cost estimates
- Interactive selection (specific workers or all)
- Cost warning before starting
- Shows updated IPs after starting

### step-323-gpu-worker-deploy-idle-monitor.sh
**Deploy idle monitoring (30min auto-shutdown)**
- Deploys auto-shutdown to all running workers
- Uses `GPU_WORKER_IDLE_TIMEOUT_MINUTES` from .env (default: 30)
- Sets up systemd service for reliability
- Only targets GPU instances, never dev instance

### step-324-gpu-worker-health-check.sh
**Comprehensive health check (GPU+API+Queue)**
- SSH connectivity test
- GPU/CUDA functionality check
- Docker container status
- FastAPI health endpoint
- Idle monitor service status
- System resources (CPU/Memory/Disk)

### step-325-gpu-worker-manage-interactive.sh
**Interactive menu for all worker operations**
- Menu-driven interface for all worker management
- Real-time cost summary
- Quick access to all worker functions
- Cost analysis and timeout configuration

### step-328-gpu-worker-stop-all.sh
**Stop all running GPU workers (cost savings)**
- Shows current cost breakdown
- Calculates savings from stopping
- Stops all workers simultaneously
- Verifies all stopped

## Destruction Scripts (9xx)

### step-980-destroy-discovery.sh
**Discover all resources from .env files**
- Scans all .env files in the project
- Identifies EC2 instances, Lambda functions, S3 buckets, etc.
- Creates comprehensive resource inventory
- Outputs JSON discovery file

### step-990-destroy-validation.sh  
**Check which resources actually exist in AWS**
- Validates discovered resources against AWS
- Calculates current costs and savings
- Identifies resources with data (S3 buckets)
- Creates destruction plan with warnings

### step-999-destroy-execute-all.sh
**Execute the destruction plan**
- Triple confirmation required
- Destroys resources in safe dependency order
- Real-time progress reporting
- Optional .env file cleanup

## Configuration Updates

### Updated .env.template files
- Added `GPU_WORKER_IDLE_TIMEOUT_MINUTES=30` to both smart-transcription-router and rnn-t templates
- Clear naming to distinguish from dev instance idle timeout

## Usage Workflow

### Daily GPU Worker Management
```bash
# Check what's running and costing money
./step-321-gpu-worker-status.sh

# Start workers for processing
./step-322-gpu-worker-start-stopped.sh

# Set up auto-shutdown (30 min default)
./step-323-gpu-worker-deploy-idle-monitor.sh

# Verify everything is healthy
./step-324-gpu-worker-health-check.sh

# Stop all workers to save money when done
./step-328-gpu-worker-stop-all.sh
```

### Interactive Management
```bash
# One-stop management console
./step-325-gpu-worker-manage-interactive.sh
```

### Complete Project Cleanup
```bash
# Discover what was created
./step-980-destroy-discovery.sh

# Validate what exists and costs money  
./step-990-destroy-validation.sh

# Destroy everything (with confirmations)
./step-999-destroy-execute-all.sh
```

## Key Features

### Cost Management
- Real-time cost tracking for all GPU instances
- Automatic idle timeout prevents forgotten instances
- Clear cost savings calculations
- Monthly/daily projections

### Safety Features
- GPU worker idle monitoring only affects GPU instances
- Dev instance is never touched by auto-shutdown
- Triple confirmation for destruction
- Resource validation before destruction
- Comprehensive logging

### User Experience
- Interactive menus for complex operations
- Clear visual feedback with colors and emojis
- Progress indicators for long operations
- Detailed error handling and recovery suggestions

### Integration
- All scripts use .env configuration
- Consistent parameter naming and defaults
- JSON output for automation
- Logging for audit trails

## Cost Savings

### Typical GPU Instance Costs
- g4dn.xlarge: $0.526/hour = $378/month if left running
- g5.xlarge: $1.006/hour = $724/month if left running  
- p3.2xlarge: $3.06/hour = $2,203/month if left running

### Auto-Shutdown Benefits
- 30-minute default timeout prevents overnight costs
- Can save $100-2000+ per month per forgotten instance
- Instances can be restarted anytime with no data loss
- Only shuts down GPU workers, never build/dev instances