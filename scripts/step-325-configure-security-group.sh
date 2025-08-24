#!/bin/bash

# step-325-configure-security-group.sh
# Configure security group for FastAPI GPU workers
# This ensures proper network access for transcription services

set -e

# Source configuration
if [ -f .env ]; then
    source .env
else
    echo "❌ Error: .env file not found"
    echo "Run ./scripts/step-000-setup-configuration.sh first"
    exit 1
fi

echo "🔐 Configuring Security Group for FastAPI Workers"
echo "================================================"

# Check if security group exists
if [ -z "${SECURITY_GROUP_ID}" ]; then
    echo "❌ Error: SECURITY_GROUP_ID not set in .env"
    exit 1
fi

echo "📋 Security Group: ${SECURITY_GROUP_ID}"
echo "🌎 Region: ${AWS_REGION}"

# Function to check if rule exists
check_rule_exists() {
    local protocol=$1
    local port=$2
    local cidr=${3:-"0.0.0.0/0"}
    
    if [ "$protocol" = "icmp" ]; then
        aws ec2 describe-security-groups \
            --group-ids ${SECURITY_GROUP_ID} \
            --region ${AWS_REGION} \
            --query "SecurityGroups[0].IpPermissions[?IpProtocol=='icmp' && IpRanges[?CidrIp=='${cidr}']]" \
            --output text 2>/dev/null | grep -q "icmp"
    else
        aws ec2 describe-security-groups \
            --group-ids ${SECURITY_GROUP_ID} \
            --region ${AWS_REGION} \
            --query "SecurityGroups[0].IpPermissions[?IpProtocol=='${protocol}' && FromPort==\`${port}\` && ToPort==\`${port}\` && IpRanges[?CidrIp=='${cidr}']]" \
            --output text 2>/dev/null | grep -q "${port}"
    fi
}

# Function to add rule if it doesn't exist
add_rule_if_missing() {
    local protocol=$1
    local port=$2
    local description=$3
    local cidr=${4:-"0.0.0.0/0"}
    
    if check_rule_exists "$protocol" "$port" "$cidr"; then
        echo "✅ Rule already exists: ${description} (${protocol}/${port})"
    else
        echo "➕ Adding rule: ${description} (${protocol}/${port})"
        
        if [ "$protocol" = "icmp" ]; then
            aws ec2 authorize-security-group-ingress \
                --group-id ${SECURITY_GROUP_ID} \
                --region ${AWS_REGION} \
                --protocol icmp \
                --port -1 \
                --cidr ${cidr} \
                --output json > /dev/null 2>&1 || {
                    echo "⚠️  Rule may already exist or error occurred"
                }
        else
            aws ec2 authorize-security-group-ingress \
                --group-id ${SECURITY_GROUP_ID} \
                --region ${AWS_REGION} \
                --protocol ${protocol} \
                --port ${port} \
                --cidr ${cidr} \
                --output json > /dev/null 2>&1 || {
                    echo "⚠️  Rule may already exist or error occurred"
                }
        fi
    fi
}

echo ""
echo "🔍 Checking current security group rules..."
aws ec2 describe-security-groups \
    --group-ids ${SECURITY_GROUP_ID} \
    --region ${AWS_REGION} \
    --query 'SecurityGroups[0].IpPermissions[*].[IpProtocol,FromPort,ToPort,IpRanges[0].CidrIp]' \
    --output table || {
        echo "❌ Failed to describe security group"
        exit 1
    }

echo ""
echo "🔧 Configuring required security group rules..."

# Add SSH access (port 22)
add_rule_if_missing "tcp" "22" "SSH access"

# Add FastAPI port (from .env or default to 8000)
FAST_API_PORT=${FAST_API_PORT:-8000}
add_rule_if_missing "tcp" "${FAST_API_PORT}" "FastAPI transcription service"

# Add ICMP for ping/health checks
add_rule_if_missing "icmp" "-1" "ICMP ping for health checks"

# Optional: Add HTTPS port if needed for future
# add_rule_if_missing "tcp" "443" "HTTPS access"

echo ""
echo "📊 Final security group configuration:"
aws ec2 describe-security-groups \
    --group-ids ${SECURITY_GROUP_ID} \
    --region ${AWS_REGION} \
    --query 'SecurityGroups[0].IpPermissions[*].[IpProtocol,FromPort,ToPort,IpRanges[0].CidrIp]' \
    --output table

echo ""
echo "✅ Security group configuration complete!"
echo ""
echo "📝 Summary:"
echo "  - SSH access on port 22"
echo "  - FastAPI service on port ${FAST_API_PORT}"
echo "  - ICMP enabled for health checks"
echo ""

# Test connectivity if instance is running
echo "🔍 Checking for running FastAPI instances..."
INSTANCE_IPS=$(aws ec2 describe-instances \
    --filters "Name=tag:Type,Values=${FAST_API_WORKER_TAG}" \
              "Name=instance-state-name,Values=running" \
    --region ${AWS_REGION} \
    --query 'Reservations[*].Instances[*].PublicIpAddress' \
    --output text 2>/dev/null)

if [ ! -z "$INSTANCE_IPS" ]; then
    echo "📡 Testing connectivity to running instances..."
    for IP in $INSTANCE_IPS; do
        echo -n "  Testing $IP: "
        if ping -c 1 -W 2 $IP > /dev/null 2>&1; then
            echo -n "ping ✅ "
            if curl -s -m 5 http://$IP:${FAST_API_PORT}/health > /dev/null 2>&1; then
                echo "API ✅"
            else
                echo "API ❌ (service may be starting)"
            fi
        else
            echo "ping ❌"
        fi
    done
else
    echo "ℹ️  No running FastAPI instances found to test"
fi

echo ""
echo "🎯 Next steps:"
echo "  1. Launch GPU instances: ./scripts/step-320-fast-api-launch-gpu-instances.sh"
echo "  2. Check health: ./scripts/step-326-fast-api-check-gpu-health.sh"
echo "  3. Test transcription: ./scripts/step-330-fast-api-test-transcription.sh"

# Show next step helper
show_next_step() {
    local current_script=$1
    local scripts_dir=$2
    
    # Extract current step number
    current_num=$(basename "$current_script" | sed 's/step-\([0-9]*\).*/\1/')
    
    # Find next script
    next_script=$(ls -1 "$scripts_dir"/step-*.sh 2>/dev/null | \
                  grep -A1 "$(basename $current_script)" | \
                  tail -1)
    
    if [ ! -z "$next_script" ] && [ "$next_script" != "$current_script" ]; then
        echo ""
        echo "📍 Next script to run:"
        echo "   $next_script"
    fi
}

show_next_step "$0" "$(dirname $0)"