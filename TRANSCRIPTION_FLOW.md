# Transcription System Flow - Complete Architecture

## High-Level Flow Diagram

```
🎤 Audio Recording
       ↓
📁 S3 Upload (chunk-001.webm)
       ↓
📡 EventBridge Event Published
       ↓
🚀 Lambda Router (with retry logic)
       ↓
🔄 Retry Mechanism + FastAPI
       ↓
📝 Individual Transcript (chunk-001.json)
       ↓
🔍 Session Completion Check
       ↓
📋 Combined Session Transcript (session-xxx.json)
       ↓
👁️ Transcription Viewer Shows Results
```

---

## Detailed Step-by-Step Process

### Phase 1: Audio Upload & Event Triggering

**Step 1: User Records Audio**
- User clicks record button in web app
- Audio recorded in 5-second chunks
- Each chunk saved locally as blob

**Step 2: Chunk Upload to S3**
- Web app calls `/api/audio/upload-chunk` 
- Gets pre-signed S3 URL
- Uploads `chunk-001.webm` to S3 path:
  ```
  s3://bucket/users/{userId}/audio/sessions/{sessionId}/chunk-001.webm
  ```

**Step 3: EventBridge Event Published**
- S3 upload triggers EventBridge event
- Event contains:
  ```json
  {
    "source": "custom.upload-service",
    "detail-type": "Audio Uploaded",
    "detail": {
      "userId": "user-123",
      "s3Location": {
        "bucket": "my-bucket", 
        "key": "users/user-123/audio/sessions/session-456/chunk-001.webm"
      }
    }
  }
  ```

### Phase 2: Lambda Router Processing (NEW RETRY LOGIC)

**Step 4: Lambda Receives Event**
- EventBridge triggers Lambda router
- Lambda extracts S3 bucket, key, userId, sessionId, chunk name

**Step 5: Idempotent Check (NEW)**
```python
# Check if transcript already exists
transcript_key = f"users/{userId}/transcripts/{sessionId}-chunk-001.json"
if s3.head_object(Bucket=bucket, Key=transcript_key):
    return "Already processed, skipping"
```
- ✅ **Skip if transcript exists** (prevents duplicate work)
- ⏭️ **Continue if transcript missing**

**Step 6: FastAPI Server Health Check**
- Lambda finds running FastAPI GPU server
- Checks `/health` endpoint
- If healthy → Proceed to transcription
- If unhealthy → Fall back to SQS queue

### Phase 3: Retry Mechanism with Exponential Backoff (NEW)

**Step 7: Transcription with Retry Logic**

```
🔄 Attempt 1 (Immediate)
├─ ✅ Success? → Continue to Step 8
└─ ❌ Failed? → Wait 1 second + jitter

🔄 Attempt 2 (After ~1s delay)  
├─ ✅ Success? → Continue to Step 8
└─ ❌ Failed? → Wait 2 seconds + jitter

🔄 Attempt 3 (After ~3s total)
├─ ✅ Success? → Continue to Step 8  
└─ ❌ Failed? → Wait 4 seconds + jitter

🔄 Attempt 4 (After ~7s total)
├─ ✅ Success? → Continue to Step 8
└─ ❌ Failed? → Fall back to SQS Queue
```

**Retry Logic Details:**
- **Base Delay**: 1 second
- **Exponential**: Each retry doubles the delay
- **Max Delay**: 8 seconds  
- **Jitter**: ±25% randomization to prevent thundering herd
- **Max Retries**: 3 attempts (4 total tries)

**Step 8: FastAPI Transcription**
- Lambda sends POST request to FastAPI:
  ```json
  {
    "s3_input_path": "s3://bucket/users/user-123/audio/sessions/session-456/chunk-001.webm",
    "s3_output_path": "s3://bucket/users/user-123/transcripts/session-456-chunk-001.json",
    "return_text": true
  }
  ```
- FastAPI downloads audio, transcribes with Whisper, uploads transcript to S3

### Phase 4: Session Completion & Auto-Combination (NEW)

**Step 9: Session Completion Check**
- After successful chunk transcription, Lambda checks:
  1. Get session metadata: How many chunks expected?
  2. Count existing transcripts for this session
  3. If `transcripts >= expected_chunks` → Trigger combination

**Step 10: Automatic Session Combination**
- Find all chunk transcripts: `session-456-chunk-001.json`, `chunk-002.json`, etc.
- Download and parse each chunk transcript
- Combine into single session transcript with:
  - Combined text
  - Adjusted timestamps (chunk 1: 0-5s, chunk 2: 5-10s, etc.)
  - Paragraph formatting for viewer
- Save to: `users/{userId}/transcripts/session-456.json`

### Phase 5: Fallback Mechanisms

**SQS Fallback (If FastAPI Fails)**
- Failed chunks sent to SQS queue
- SQS worker processes later (batch mode)
- Higher reliability, lower priority

**EventBridge Retry (If Lambda Fails)**  
- If Lambda times out or crashes completely
- EventBridge automatically retries the entire invocation
- Separate from internal FastAPI retries

---

## Success Rate Comparison

### Before Retry Mechanism:
```
36 chunks uploaded → 28 transcribed (78% success)
├─ 7 chunks failed (first chunks, server overload, timeouts)
├─ Session transcript: Manual combination required
└─ Viewer shows: "Processing..." indefinitely
```

### After Retry Mechanism:
```
36 chunks uploaded → ~34 transcribed (95%+ expected success)
├─ 1st attempt: ~28 succeed immediately
├─ Retry attempts: ~6 more succeed after delays  
├─ SQS fallback: Remaining 2 chunks processed later
├─ Session transcript: Created automatically
└─ Viewer shows: Actual transcript content
```

---

## Error Handling Scenarios

### Scenario A: Transient Network Error
1. Chunk upload succeeds → EventBridge event fired
2. Lambda attempt 1: Network timeout → Retry in 1s
3. Lambda attempt 2: Success → Transcript created
4. Result: ✅ Chunk transcribed successfully

### Scenario B: FastAPI Server Overloaded
1. Lambda attempt 1: 503 Server Busy → Retry in 1s  
2. Lambda attempt 2: Still busy → Retry in 2s
3. Lambda attempt 3: Success → Transcript created
4. Result: ✅ Chunk transcribed with slight delay

### Scenario C: Persistent Failure
1. Lambda attempts 1-4: All fail
2. Lambda sends chunk to SQS queue
3. Background worker processes from queue later
4. Result: ✅ Chunk eventually transcribed (batch mode)

### Scenario D: Duplicate Event
1. EventBridge sends same event twice (edge case)
2. Lambda attempt 1: Transcribes successfully
3. Lambda attempt 2: Sees transcript exists → Skip
4. Result: ✅ No duplicate work, same transcript

---

## File Structure After Processing

```
S3 Bucket Structure:
├── users/
│   └── user-123/
│       ├── audio/sessions/session-456/
│       │   ├── chunk-001.webm (original audio)
│       │   ├── chunk-002.webm
│       │   ├── ...
│       │   └── metadata.json (expected chunk count)
│       └── transcripts/
│           ├── session-456-chunk-001.json (individual)
│           ├── session-456-chunk-002.json (individual) 
│           ├── ...
│           └── session-456.json (combined session transcript)
```

The transcription viewer looks for `session-456.json` to display results. If this file exists, it shows the transcript. If missing, it shows "Processing..."

---

## Key Improvements

1. **🔄 Exponential Backoff**: Handles transient failures gracefully
2. **⚡ Idempotent Processing**: Prevents duplicate transcriptions
3. **🔄 Automatic Session Combination**: No manual intervention needed  
4. **📊 Higher Success Rate**: From ~78% to ~95%+ expected
5. **🚨 Better Error Handling**: Multiple fallback mechanisms
6. **📝 Comprehensive Logging**: Easier debugging and monitoring

This system should dramatically reduce "processing" messages and improve overall transcription reliability.