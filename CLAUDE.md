# CLAUDE.md - Smart Transcription Router Project Context

## Architecture
- **Lambda Router**: Checks FastAPI server health and routes requests accordingly
- **FastAPI Server**: GPU-accelerated transcription using WhisperX (when available)
- **SQS Queue**: Reliable message queuing for batch processing (when server is down)
- **EventBridge Integration**: Receives audio upload events from cognito-lambda-s3-webserver-cloudfront

## Remember
- be sure to set variables in the .env file.  DO NOT HARDCODE THINGS IN THE SCRIPT!
- always checkin the code and push this to git. Your Mission is to ensure what you test is encoded into the step-xxx scripts so that a new user who checks out the code doesn't have to fix up scirpts to operate.
- if you are doing something first test it out by executing it and if that succeds go back an implement it into code and check that in.
- be sure to update the readme so that a user would easily understand it.
- if you have a question clarify it by asking clarifying questions.
- each step-xxx script is executed sequentially, be sure that you order this correctly and a new user who just checked out the code could run the script.
- number each script by 10s so that way if needed you could go back and insert scripts.
- write scripts also to test and verify, and if you are testing and its useful, instead write a step-xxx script to execute it, and that way future users can test functionality




