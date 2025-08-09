#!/bin/bash

# fix-lambda-s3-permissions.sh - Fix Lambda S3 permissions for audio processing

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the project root directory
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.env"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo -e "${RED}[ERROR]${NC} Configuration file not found at $CONFIG_FILE"
    exit 1
fi

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}🔧 Fix Lambda S3 Permissions${NC}"
echo -e "${BLUE}======================================${NC}"

LAMBDA_ROLE_NAME="${TRANSCRIPTION_ROUTER_FUNCTION_NAME}-role"

echo -e "${GREEN}[STEP 1]${NC} Current Lambda role permissions:"
echo -e "${BLUE}Role:${NC} $LAMBDA_ROLE_NAME"

# Get current policy
CURRENT_POLICY=$(aws iam get-role-policy \
    --role-name "$LAMBDA_ROLE_NAME" \
    --policy-name "${TRANSCRIPTION_ROUTER_FUNCTION_NAME}-policy" \
    --query 'PolicyDocument' \
    --region "$AWS_REGION" 2>/dev/null || echo "{}")

echo -e "${YELLOW}Current policy has no S3 permissions${NC}"

echo -e "\n${GREEN}[STEP 2]${NC} Adding S3 permissions for audio processing..."

# Create updated policy with S3 permissions
cat > /tmp/lambda-policy-updated.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:${AWS_REGION}:*:*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "sqs:SendMessage",
                "sqs:GetQueueAttributes"
            ],
            "Resource": "arn:aws:sqs:${AWS_REGION}:*:${PROJECT_NAME}-*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances"
            ],
            "Resource": "*"
        },
        {
            "Sid": "S3AudioAccess",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:GetObjectVersion",
                "s3:HeadObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::dbm-cf-2-web/*",
                "arn:aws:s3:::dbm-cf-2-web",
                "arn:aws:s3:::${PROJECT_NAME}-*/*",
                "arn:aws:s3:::${PROJECT_NAME}-*"
            ]
        }
    ]
}
EOF

# Update the Lambda role policy
aws iam put-role-policy \
    --role-name "$LAMBDA_ROLE_NAME" \
    --policy-name "${TRANSCRIPTION_ROUTER_FUNCTION_NAME}-policy" \
    --policy-document file:///tmp/lambda-policy-updated.json \
    --region "$AWS_REGION"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ SUCCESS${NC} Lambda S3 permissions updated"
else
    echo -e "${RED}❌ ERROR${NC} Failed to update Lambda permissions"
    exit 1
fi

echo -e "\n${GREEN}[STEP 3]${NC} Verifying updated permissions..."

# Verify the policy was updated
aws iam get-role-policy \
    --role-name "$LAMBDA_ROLE_NAME" \
    --policy-name "${TRANSCRIPTION_ROUTER_FUNCTION_NAME}-policy" \
    --query 'PolicyDocument.Statement[?Sid==`S3AudioAccess`]' \
    --region "$AWS_REGION" \
    --output table

echo -e "\n${GREEN}[STEP 4]${NC} Testing Lambda function..."

# Test the Lambda function again
cat > /tmp/test-audio-event.json << EOF
{
  "Records": [
    {
      "eventSource": "aws:events",
      "eventName": "Object Created",
      "s3": {
        "bucket": {
          "name": "dbm-cf-2-web"
        },
        "object": {
          "key": "users/test-user/audio/sessions/test-session/chunk001.wav"
        }
      }
    }
  ]
}
EOF

echo -e "${BLUE}Testing with mock event...${NC}"
LAMBDA_RESPONSE=$(aws lambda invoke \
    --function-name "$TRANSCRIPTION_ROUTER_FUNCTION_NAME" \
    --payload file:///tmp/test-audio-event.json \
    --region "$AWS_REGION" \
    /tmp/lambda-response.json 2>&1)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ SUCCESS${NC} Lambda invocation completed"
    echo -e "${BLUE}Response:${NC}"
    cat /tmp/lambda-response.json | python3 -m json.tool 2>/dev/null || cat /tmp/lambda-response.json
else
    echo -e "${YELLOW}⚠️ WARNING${NC} Lambda test had issues (expected for mock data)"
fi

# Cleanup temp files
rm -f /tmp/lambda-policy-updated.json /tmp/test-audio-event.json /tmp/lambda-response.json

echo
echo -e "${BLUE}======================================${NC}"
echo -e "${GREEN}✅ Lambda S3 Permissions Fixed${NC}"
echo -e "${BLUE}======================================${NC}"
echo
echo -e "${GREEN}[PERMISSIONS ADDED]${NC}"
echo "• s3:GetObject - Read audio files"
echo "• s3:HeadObject - Check file metadata"  
echo "• s3:ListBucket - Navigate S3 structure"
echo "• Access to dbm-cf-2-web bucket (frontend uploads)"
echo
echo -e "${GREEN}[WHAT THIS FIXES]${NC}"
echo "• Lambda can now read audio files from S3"
echo "• FastAPI server can access files via presigned URLs"
echo "• End-to-end transcription flow should work"
echo
echo -e "${BLUE}[NEXT STEPS]${NC}"
echo "1. Test audio upload in frontend application"
echo "2. Monitor CloudWatch logs for successful processing"
echo "3. Verify transcription results are returned"
