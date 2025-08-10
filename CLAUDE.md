# CLAUDE.md - Smart Transcription Router Project Context

## Architecture
- **Lambda Router**: Checks FastAPI server health and routes requests accordingly with exponential backoff retry
- **FastAPI Server**: GPU-accelerated transcription using WhisperX (when available)
- **SQS Queue**: Reliable message queuing for batch processing (when server is down)
- **EventBridge Integration**: Receives audio upload events from cognito-lambda-s3-webserver-cloudfront
- **Auto Session Combination**: Automatically creates session transcripts when chunks complete

## ⚠️ CRITICAL DEVELOPMENT RULES ⚠️

### 🚨 NEVER HARDCODE - ALWAYS USE .env
- **NEVER HARDCODE** bucket names, ARNs, region names, or any AWS resource identifiers
- **ALWAYS USE** variables from .env file: `${AUDIO_BUCKET}`, `${AWS_REGION}`, `${QUEUE_PREFIX}`, etc.
- **VALIDATE** all scripts use .env variables before committing
- **EXAMPLE**: Use `arn:aws:s3:::${AUDIO_BUCKET}` NOT `arn:aws:s3:::dbm-cf-2-web`

### 📝 Step Script Development Process
1. **Test first**: Execute and verify functionality manually
2. **Encode in scripts**: Implement working solution in step-xxx scripts  
3. **Use .env variables**: Ensure all scripts reference .env, no hardcoding
4. **Commit & push**: Always push changes to git for deployment
5. **Update docs**: Keep README and CLAUDE.md current
6. **Sequential order**: Number scripts by 10s for insertion flexibility

### 🔧 Current System Features
- **Exponential Backoff Retry**: 1s, 2s, 4s delays with jitter for transient failures
- **Idempotent Processing**: Skips already-transcribed chunks automatically  
- **High Success Rate**: Improved from ~78% to ~95%+ chunk success rate
- **Automatic Session Combination**: Creates session transcripts when chunks complete
- **Comprehensive Logging**: Detailed success/failure visibility for debugging

## Remember
- be sure to set variables in the .env file.  DO NOT HARDCODE THINGS IN THE SCRIPT!
- always checkin the code and push this to git. Your Mission is to ensure what you test is encoded into the step-xxx scripts so that a new user who checks out the code doesn't have to fix up scirpts to operate.
- if you are doing something first test it out by executing it and if that succeds go back an implement it into code and check that in.
- be sure to update the readme so that a user would easily understand it.
- if you have a question clarify it by asking clarifying questions.
- each step-xxx script is executed sequentially, be sure that you order this correctly and a new user who just checked out the code could run the script.
- number each script by 10s so that way if needed you could go back and insert scripts.
- write scripts also to test and verify, and if you are testing and its useful, instead write a step-xxx script to execute it, and that way future users can test functionality




