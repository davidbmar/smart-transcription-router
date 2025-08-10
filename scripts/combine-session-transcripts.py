#!/usr/bin/env python3
"""
Combine individual chunk transcripts into a session-level transcript
compatible with the transcription viewer.
"""
import boto3
import json
import re
from typing import List, Dict, Any

s3 = boto3.client('s3')

def find_chunk_transcripts(bucket: str, user_id: str, session_id: str) -> List[Dict]:
    """Find all chunk transcript files for a session"""
    # Try both transcripts and transcriptions directories
    prefixes = [
        f"users/{user_id}/transcripts/{session_id}-chunk-",
        f"users/{user_id}/transcriptions/{session_id}-chunk-"
    ]
    
    chunk_files = []
    
    for prefix in prefixes:
        try:
            response = s3.list_objects_v2(Bucket=bucket, Prefix=prefix)
            if 'Contents' in response:
                for obj in response['Contents']:
                    key = obj['Key']
                    # Extract chunk number from filename
                    match = re.search(r'chunk-(\d+)\.json$', key)
                    if match:
                        chunk_num = int(match.group(1))
                        chunk_files.append({
                            'key': key,
                            'chunk_number': chunk_num
                        })
        except Exception as e:
            print(f"Error listing chunk files with prefix {prefix}: {e}")
    
    # Sort by chunk number and remove duplicates
    chunk_files.sort(key=lambda x: x['chunk_number'])
    return chunk_files

def download_transcript(bucket: str, key: str) -> Dict[str, Any]:
    """Download and parse a transcript file"""
    try:
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        return json.loads(content)
    except Exception as e:
        print(f"Error downloading {key}: {e}")
        return {}

def combine_transcripts(chunk_transcripts: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Combine individual chunk transcripts into a session transcript"""
    if not chunk_transcripts:
        return {}
    
    # Start with the first transcript as base
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
    paragraph_id = 0
    
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
                # Adjust timestamps to be relative to session start
                start_time = current_time_offset + chunk['timestamp'][0]
                end_time = current_time_offset + chunk['timestamp'][1]
                
                combined['chunks'].append({
                    'timestamp': [start_time, end_time],
                    'text': chunk['text']
                })
                
                # Create paragraph format for viewer compatibility
                words = chunk['text'].split()
                word_objects = []
                
                # Estimate word timing within the chunk
                chunk_duration = end_time - start_time
                if len(words) > 0:
                    time_per_word = chunk_duration / len(words)
                    for j, word in enumerate(words):
                        word_time = start_time + (j * time_per_word)
                        word_objects.append({
                            'w': word,
                            't': word_time
                        })
                
                # Add as paragraph
                combined['paragraphs'].append({
                    'speaker': 'Speaker',
                    'start': start_time,
                    'end': end_time,
                    'text': chunk['text'],
                    'words': word_objects
                })
        
        # Update time offset for next chunk (assume ~5 seconds per chunk)
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
    
    return combined

def save_session_transcript(bucket: str, user_id: str, session_id: str, combined_transcript: Dict[str, Any]):
    """Save the combined transcript to S3"""
    key = f"users/{user_id}/transcripts/{session_id}.json"
    
    try:
        s3.put_object(
            Bucket=bucket,
            Key=key,
            Body=json.dumps(combined_transcript, indent=2),
            ContentType='application/json'
        )
        print(f"✅ Saved session transcript: {key}")
    except Exception as e:
        print(f"❌ Error saving session transcript: {e}")

def process_session(bucket: str, user_id: str, session_id: str):
    """Process a complete session: combine chunks into session transcript"""
    print(f"🔄 Processing session: {session_id}")
    
    # Find all chunk transcripts
    chunk_files = find_chunk_transcripts(bucket, user_id, session_id)
    if not chunk_files:
        print(f"❌ No chunk transcripts found for session {session_id}")
        return
    
    print(f"📁 Found {len(chunk_files)} chunk transcripts")
    
    # Download all chunk transcripts
    chunk_transcripts = []
    for chunk_file in chunk_files:
        transcript = download_transcript(bucket, chunk_file['key'])
        if transcript:
            chunk_transcripts.append(transcript)
    
    if not chunk_transcripts:
        print("❌ No valid transcripts to combine")
        return
    
    # Combine transcripts
    combined = combine_transcripts(chunk_transcripts)
    if not combined:
        print("❌ Failed to combine transcripts")
        return
    
    # Save combined transcript
    save_session_transcript(bucket, user_id, session_id, combined)

if __name__ == "__main__":
    import sys
    
    if len(sys.argv) != 4:
        print("Usage: python3 combine-session-transcripts.py <bucket> <user_id> <session_id>")
        sys.exit(1)
    
    bucket = sys.argv[1]
    user_id = sys.argv[2]
    session_id = sys.argv[3]
    
    process_session(bucket, user_id, session_id)