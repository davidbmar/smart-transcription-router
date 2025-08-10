import json
import os
import boto3
import requests
from datetime import datetime
import subprocess
import tempfile
import time
import random

# Initialize AWS clients
sqs = boto3.client('sqs')
ec2 = boto3.client('ec2')
s3 = boto3.client('s3')

# Environment variables
SQS_QUEUE_URL = os.environ.get('SQS_QUEUE_URL')
FAST_API_TAG = os.environ.get('FAST_API_TAG', 'fast-api-worker')
FAST_API_PORT = os.environ.get('FAST_API_PORT', '8000')
HEALTH_CHECK_TIMEOUT = int(os.environ.get('HEALTH_CHECK_TIMEOUT', '2'))

def get_fastapi_server_url():
    """Get the URL of a running FastAPI server if available"""
    try:
        # Find running FastAPI instances
        response = ec2.describe_instances(
            Filters=[
                {'Name': 'tag:Type', 'Values': [FAST_API_TAG]},
                {'Name': 'instance-state-name', 'Values': ['running']}
            ]
        )
        
        # Get the first available instance
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                public_ip = instance.get('PublicIpAddress')
                if public_ip:
                    return f"http://{public_ip}:{FAST_API_PORT}"
        
        return None
    except Exception as e:
        print(f"Error finding FastAPI server: {e}")
        return None

def check_server_health(server_url):
    """Check if FastAPI server is healthy"""
    if not server_url:
        return False
    
    try:
        response = requests.get(
            f"{server_url}/health",
            timeout=HEALTH_CHECK_TIMEOUT
        )
        return response.status_code == 200
    except:
        return False

def check_session_completion(s3_bucket, user_id, session_id):
    """Check if a session is complete and trigger combination if needed"""
    try:
        print(f"Checking completion for session {session_id} in bucket {s3_bucket}")
        # First, get session metadata to see expected chunk count
        metadata_key = f"users/{user_id}/audio/sessions/{session_id}/metadata.json"
        
        try:
            metadata_response = s3.get_object(Bucket=s3_bucket, Key=metadata_key)
            metadata = json.loads(metadata_response['Body'].read().decode('utf-8'))
            expected_chunks = metadata.get('chunkCount', 0)
            
            if expected_chunks == 0:
                print(f"Session {session_id} has no expected chunk count, skipping completion check")
                return False
        except s3.exceptions.NoSuchKey:
            print(f"No metadata found for session {session_id}, cannot determine completion")
            return False
        
        # Count existing transcripts for this session
        transcript_prefix = f"users/{user_id}/transcripts/{session_id}-chunk-"
        
        response = s3.list_objects_v2(Bucket=s3_bucket, Prefix=transcript_prefix)
        existing_transcripts = len(response.get('Contents', []))
        
        print(f"Session {session_id}: {existing_transcripts}/{expected_chunks} chunks transcribed")
        
        # If we have all expected chunks, check if session transcript exists
        if existing_transcripts >= expected_chunks:
            session_transcript_key = f"users/{user_id}/transcripts/{session_id}.json"
            
            try:
                s3.head_object(Bucket=s3_bucket, Key=session_transcript_key)
                print(f"Session transcript already exists for {session_id}")
                return False
            except s3.exceptions.NoSuchKey:
                print(f"Session {session_id} is complete, triggering combination")
                return trigger_session_combination(s3_bucket, user_id, session_id)
        
        return False
        
    except Exception as e:
        print(f"Error checking session completion: {e}")
        return False

def trigger_session_combination(s3_bucket, user_id, session_id):
    """Trigger session transcript combination"""
    try:
        # Download the combiner script from our repository or use inline Python
        # For now, implement the combination logic inline
        
        # Find all chunk transcripts
        prefixes = [
            f"users/{user_id}/transcripts/{session_id}-chunk-",
            f"users/{user_id}/transcriptions/{session_id}-chunk-"
        ]
        
        chunk_files = []
        
        for prefix in prefixes:
            try:
                response = s3.list_objects_v2(Bucket=s3_bucket, Prefix=prefix)
                if 'Contents' in response:
                    for obj in response['Contents']:
                        key = obj['Key']
                        # Extract chunk number from filename
                        import re
                        match = re.search(r'chunk-(\d+)\.json$', key)
                        if match:
                            chunk_num = int(match.group(1))
                            chunk_files.append({
                                'key': key,
                                'chunk_number': chunk_num
                            })
            except Exception as e:
                print(f"Error listing chunk files with prefix {prefix}: {e}")
        
        # Sort by chunk number
        chunk_files.sort(key=lambda x: x['chunk_number'])
        
        if not chunk_files:
            print(f"No chunk transcripts found for session {session_id}")
            return False
        
        print(f"Found {len(chunk_files)} chunk transcripts, combining...")
        
        # Download all chunk transcripts
        chunk_transcripts = []
        for chunk_file in chunk_files:
            try:
                response = s3.get_object(Bucket=s3_bucket, Key=chunk_file['key'])
                content = response['Body'].read().decode('utf-8')
                transcript = json.loads(content)
                chunk_transcripts.append(transcript)
            except Exception as e:
                print(f"Error downloading {chunk_file['key']}: {e}")
        
        if not chunk_transcripts:
            print("No valid transcripts to combine")
            return False
        
        # Combine transcripts (simplified version)
        combined = {
            'text': '',
            'chunks': [],
            'paragraphs': [],
            'metadata': {
                'total_chunks': len(chunk_transcripts),
                'duration': 0,
                'wordCount': 0
            }
        }
        
        current_time_offset = 0.0
        
        for i, transcript in enumerate(chunk_transcripts):
            if not transcript or 'chunks' not in transcript:
                continue
            
            # Add to combined text
            chunk_text = transcript.get('text', '').strip()
            if chunk_text:
                if combined['text']:
                    combined['text'] += ' ' + chunk_text
                else:
                    combined['text'] = chunk_text
            
            # Process chunks with time offset
            for chunk in transcript['chunks']:
                if 'timestamp' in chunk and len(chunk['timestamp']) == 2:
                    start_time = current_time_offset + chunk['timestamp'][0]
                    end_time = current_time_offset + chunk['timestamp'][1]
                    
                    combined['chunks'].append({
                        'timestamp': [start_time, end_time],
                        'text': chunk['text']
                    })
                    
                    # Create paragraph format
                    words = chunk['text'].split()
                    word_objects = []
                    
                    chunk_duration = end_time - start_time
                    if len(words) > 0:
                        time_per_word = chunk_duration / len(words)
                        for j, word in enumerate(words):
                            word_time = start_time + (j * time_per_word)
                            word_objects.append({
                                'w': word,
                                't': word_time
                            })
                    
                    combined['paragraphs'].append({
                        'speaker': 'Speaker',
                        'start': start_time,
                        'end': end_time,
                        'text': chunk['text'],
                        'words': word_objects
                    })
            
            # Update time offset (assume 5 seconds per chunk)
            chunk_duration = 5.0
            if transcript.get('chunks'):
                last_chunk = transcript['chunks'][-1]
                if 'timestamp' in last_chunk and len(last_chunk['timestamp']) == 2:
                    chunk_duration = last_chunk['timestamp'][1]
            
            current_time_offset += chunk_duration
        
        # Update metadata
        combined['metadata']['duration'] = current_time_offset
        combined['metadata']['wordCount'] = len(combined['text'].split())
        combined['device'] = chunk_transcripts[0].get('device', 'unknown')
        combined['model'] = chunk_transcripts[0].get('model', 'unknown')
        combined['timestamp'] = chunk_transcripts[-1].get('timestamp', '')
        
        # Save combined transcript
        session_key = f"users/{user_id}/transcripts/{session_id}.json"
        
        s3.put_object(
            Bucket=s3_bucket,
            Key=session_key,
            Body=json.dumps(combined, indent=2),
            ContentType='application/json'
        )
        
        print(f"✅ Created session transcript: {session_key}")
        return True
        
    except Exception as e:
        print(f"Error combining session transcripts: {e}")
        return False

def retry_with_exponential_backoff(func, max_retries=3, base_delay=1.0, max_delay=16.0, jitter=True):
    """
    Retry a function with exponential backoff
    
    Args:
        func: Function to retry (should return tuple of (success, result, error))
        max_retries: Maximum number of retry attempts
        base_delay: Initial delay in seconds
        max_delay: Maximum delay in seconds
        jitter: Add random jitter to prevent thundering herd
    """
    for attempt in range(max_retries + 1):
        try:
            success, result, error = func()
            if success:
                return result
            
            if attempt == max_retries:
                print(f"Final attempt failed: {error}")
                raise Exception(error)
            
            # Calculate exponential backoff delay
            delay = min(base_delay * (2 ** attempt), max_delay)
            if jitter:
                delay = delay * (0.5 + random.random() * 0.5)  # Add ±25% jitter
            
            print(f"Attempt {attempt + 1} failed: {error}. Retrying in {delay:.2f}s...")
            time.sleep(delay)
            
        except Exception as e:
            if attempt == max_retries:
                print(f"Retry mechanism failed: {e}")
                raise
            
            delay = min(base_delay * (2 ** attempt), max_delay)
            if jitter:
                delay = delay * (0.5 + random.random() * 0.5)
            
            print(f"Exception on attempt {attempt + 1}: {e}. Retrying in {delay:.2f}s...")
            time.sleep(delay)

def try_fastapi_transcription(server_url, request_data):
    """
    Single attempt at FastAPI transcription
    Returns: (success: bool, result: dict, error: str)
    """
    try:
        response = requests.post(
            f"{server_url}/transcribe-s3",
            json=request_data,
            timeout=30
        )
        
        if response.status_code == 200:
            return True, response.json(), None
        else:
            error_msg = f"FastAPI returned {response.status_code}: {response.text}"
            return False, None, error_msg
            
    except requests.exceptions.Timeout:
        return False, None, "FastAPI request timed out"
    except requests.exceptions.ConnectionError:
        return False, None, "Failed to connect to FastAPI server"
    except Exception as e:
        return False, None, f"FastAPI request failed: {str(e)}"

def send_to_fastapi(server_url, event_data):
    """Send transcription request directly to FastAPI server"""
    try:
        # Extract S3 information from event (handle both formats)
        s3_bucket = event_data.get('s3_bucket')
        s3_key = event_data.get('s3_key')
        
        # Check for cognito-lambda-s3 event format
        if not s3_bucket and event_data.get('s3Location'):
            s3_bucket = event_data['s3Location'].get('bucket')
            s3_key = event_data['s3Location'].get('key')
        
        if not s3_bucket or not s3_key:
            raise ValueError("Missing S3 bucket or key in event data")
        
        # Extract user ID from the S3 key to build proper output path
        # Expected format: users/{userId}/audio/sessions/{sessionId}/chunk-XXX.webm
        user_id = None
        session_id = None
        chunk_name = None
        
        if s3_key.startswith('users/') and '/audio/sessions/' in s3_key:
            parts = s3_key.split('/')
            if len(parts) >= 5:
                user_id = parts[1]  # users/{userId}/...
                session_id = parts[4]  # .../sessions/{sessionId}/...
                chunk_name = parts[-1].replace('.webm', '')  # chunk-001.webm -> chunk-001
        
        # Build proper output path under user's transcripts directory (note: transcripts not transcriptions)
        if user_id and session_id and chunk_name:
            output_path = f"s3://{s3_bucket}/users/{user_id}/transcripts/{session_id}-{chunk_name}.json"
            transcript_key = f"users/{user_id}/transcripts/{session_id}-{chunk_name}.json"
            
            # Check if transcript already exists (idempotent processing)
            try:
                s3.head_object(Bucket=s3_bucket, Key=transcript_key)
                print(f"Transcript already exists for {chunk_name}, skipping transcription")
                return {
                    'statusCode': 200,
                    'body': json.dumps({
                        'message': 'Transcript already exists',
                        'method': 'skipped',
                        's3_output_path': output_path
                    })
                }
            except s3.exceptions.NoSuchKey:
                # Transcript doesn't exist, proceed with transcription
                print(f"No existing transcript found for {chunk_name}, proceeding with transcription")
                pass
            except Exception as e:
                print(f"Error checking for existing transcript: {e}")
                # Continue with transcription if we can't check
                pass
        else:
            # Fallback to original logic if parsing fails
            output_path = f"s3://{s3_bucket}/transcripts/{s3_key}.json"
            print(f"Warning: Could not parse user structure from key {s3_key}, using fallback path")
        
        # Prepare request for FastAPI
        request_data = {
            "s3_input_path": f"s3://{s3_bucket}/{s3_key}",
            "s3_output_path": output_path,
            "return_text": True
        }
        
        # Retry FastAPI transcription with exponential backoff
        print(f"Starting transcription for {chunk_name} with retry mechanism")
        
        def attempt_transcription():
            return try_fastapi_transcription(server_url, request_data)
        
        try:
            # Attempt transcription with retries (3 attempts: immediate, +1s, +2s, +4s delays)
            result = retry_with_exponential_backoff(
                attempt_transcription,
                max_retries=3,
                base_delay=1.0,
                max_delay=8.0
            )
            
            print(f"FastAPI transcription successful after retries")
            
            # After successful transcription, check if session is complete
            if user_id and session_id:
                try:
                    print(f"Checking session completion for {session_id}")
                    check_session_completion(s3_bucket, user_id, session_id)
                except Exception as session_error:
                    print(f"Error checking session completion: {session_error}")
                    # Don't fail the main transcription, just log the error
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Transcription completed',
                    'method': 'direct-with-retry',
                    'result': result
                })
            }
            
        except Exception as fastapi_error:
            # FastAPI failed after all retries, fall back to SQS
            print(f"FastAPI failed after retries: {fastapi_error}. Falling back to SQS")
            return send_to_sqs(event_data)
            
    except Exception as e:
        print(f"Error sending to FastAPI: {e}")
        raise

def send_to_sqs(event_data):
    """Send transcription request to SQS queue"""
    try:
        # Normalize event data format for SQS
        normalized_data = event_data.copy()
        
        # Handle cognito-lambda-s3 format
        if 's3Location' in event_data and 's3_bucket' not in event_data:
            normalized_data['s3_bucket'] = event_data['s3Location'].get('bucket')
            normalized_data['s3_key'] = event_data['s3Location'].get('key')
        
        # Add metadata for batch processing
        message_body = {
            **normalized_data,
            'queued_at': datetime.utcnow().isoformat(),
            'processing_type': 'batch'
        }
        
        # Send to SQS
        response = sqs.send_message(
            QueueUrl=SQS_QUEUE_URL,
            MessageBody=json.dumps(message_body),
            MessageAttributes={
                'event_type': {
                    'StringValue': event_data.get('event_type', 'audio_upload'),
                    'DataType': 'String'
                }
            }
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Request queued for batch processing',
                'method': 'sqs',
                'messageId': response['MessageId']
            })
        }
        
    except Exception as e:
        print(f"Error sending to SQS: {e}")
        raise

def lambda_handler(event, context):
    """
    Lambda function that routes transcription requests to either
    FastAPI (if available) or SQS queue (for batch processing)
    """
    print(f"Received event: {json.dumps(event)}")
    
    try:
        # Parse EventBridge event
        if 'detail' in event:
            event_data = event['detail']
        else:
            event_data = event
        
        # Check if we should force batch processing
        force_batch = event_data.get('force_batch', False)
        
        if not force_batch:
            # Try to find and use FastAPI server
            server_url = get_fastapi_server_url()
            
            if server_url and check_server_health(server_url):
                print(f"FastAPI server available at {server_url}, using direct processing")
                return send_to_fastapi(server_url, event_data)
        
        # Fall back to SQS queue
        print("FastAPI server not available or batch processing requested, queuing to SQS")
        return send_to_sqs(event_data)
        
    except Exception as e:
        print(f"Error in lambda handler: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }