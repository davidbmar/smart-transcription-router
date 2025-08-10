import json
import os
import boto3
import requests
from datetime import datetime

# Initialize AWS clients
sqs = boto3.client('sqs')
ec2 = boto3.client('ec2')

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
        
        # Send to FastAPI
        response = requests.post(
            f"{server_url}/transcribe-s3",
            json=request_data,
            timeout=30  # Longer timeout for transcription
        )
        
        if response.status_code == 200:
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Transcription completed',
                    'method': 'direct',
                    'result': response.json()
                })
            }
        else:
            raise Exception(f"FastAPI returned {response.status_code}: {response.text}")
            
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