#!/bin/bash

# common-functions.sh - Standardized messaging and utility functions for all scripts
# Source this file in other scripts with: source "$(dirname "$0")/common-functions.sh"

# Standard color definitions
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export RED='\033[0;31m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export NC='\033[0m' # No Color

# Standard messaging functions
print_header() {
    echo -e "${BLUE}======================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo
}

print_step() {
    echo -e "${GREEN}[STEP $1]${NC} $2"
}

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_note() {
    echo -e "${CYAN}[NOTE]${NC} $1"
}

print_separator() {
    echo -e "${BLUE}======================================${NC}"
}

print_next_step() {
    echo
    echo -e "${GREEN}[NEXT STEP]${NC}"
    echo "$1"
}

print_summary() {
    echo
    print_separator
    echo -e "${GREEN}✅ $1${NC}"
    print_separator
    echo
}

# Configuration loading with error handling
load_config() {
    local config_file="${1:-.env}"
    
    if [ -f "$config_file" ]; then
        source "$config_file"
        print_status "Configuration loaded from $config_file"
    else
        print_error "Configuration file not found: $config_file"
        echo "Run ./scripts/step-000-setup-configuration.sh first."
        exit 1
    fi
}

# Status tracking functions
update_status() {
    local step="$1"
    local status_file="${2:-.setup-status}"
    echo "${step}-completed=$(date)" >> "$status_file"
}

check_prerequisites() {
    local required_step="$1"
    local status_file="${2:-.setup-status}"
    
    if [ ! -f "$status_file" ]; then
        print_error "Setup status file not found. Run step-000-setup-configuration.sh first."
        exit 1
    fi
    
    if ! grep -q "${required_step}-completed" "$status_file"; then
        print_error "Prerequisite step $required_step not completed."
        echo "Please run the required step first."
        exit 1
    fi
}

# Generate timestamp-based version tag with collision detection
generate_version_tag() {
    local prefix="$1"      # e.g., "s3", "gpu", "worker"
    local repo_name="$2"   # ECR repository name
    local region="$3"      # AWS region
    
    local timestamp=$(date +"%Y.%m.%d.%H%M")
    local version_tag="${timestamp}"
    
    # Add prefix if provided
    if [ -n "$prefix" ]; then
        version_tag="${timestamp}-${prefix}"
    fi
    
    # Check if tag exists in ECR to avoid conflicts
    if [ -n "$repo_name" ] && [ -n "$region" ]; then
        local existing_tags=$(aws ecr describe-images \
            --repository-name "$repo_name" \
            --region "$region" \
            --query 'imageDetails[*].imageTags[*]' \
            --output text 2>/dev/null | tr '\t' '\n' | sort -rV)
        
        if echo "$existing_tags" | grep -q "^$version_tag$"; then
            # Add timestamp suffix for uniqueness
            version_tag="${version_tag}-$(date +%s | tail -c 3)"
        fi
    fi
    
    echo "$version_tag"
}

# Update .env file with new image tag
update_env_image_tag() {
    local var_name="$1"    # e.g., "FAST_API_DOCKER_IMAGE_TAG"
    local tag_value="$2"   # e.g., "2025.08.08.1430-s3"
    local env_file="${3:-.env}"  # Default to .env
    
    if [ -f "$env_file" ]; then
        if grep -q "${var_name}=" "$env_file"; then
            # Update existing variable
            if [[ "$OSTYPE" == "darwin"* ]]; then
                # macOS sed requires -i ''
                sed -i '' "s/${var_name}=.*/${var_name}=\"$tag_value\"/" "$env_file"
            else
                # Linux sed
                sed -i "s/${var_name}=.*/${var_name}=\"$tag_value\"/" "$env_file"
            fi
        else
            # Add new variable
            echo "export ${var_name}=\"$tag_value\"" >> "$env_file"
        fi
        print_success "Updated $var_name=$tag_value in $env_file"
        return 0
    else
        print_error "$env_file file not found!"
        return 1
    fi
}

# Find the latest version tag in ECR (when absolutely necessary)
# BEST PRACTICE: Only use this for discovery - always pin to specific versions in deployment
find_latest_image_version() {
    local repo_name="$1"   # ECR repository name
    local region="$2"      # AWS region
    local tag_pattern="$3" # Optional: filter pattern (e.g., "-s3")
    
    print_note "🔍 SEARCHING FOR LATEST VERSION (for reference only)"
    print_warning "Best Practice: Always pin to specific versions in production"
    print_warning "This function is for discovery only - never deploy with 'latest'"
    
    if [ -z "$repo_name" ] || [ -z "$region" ]; then
        print_error "Repository name and region required"
        return 1
    fi
    
    local query='imageDetails[*].imageTags[*]'
    local latest_tag=""
    
    # Get all tags, filter by pattern if provided, sort by version
    local all_tags=$(aws ecr describe-images \
        --repository-name "$repo_name" \
        --region "$region" \
        --query "$query" \
        --output text 2>/dev/null | tr '\t' '\n')
    
    if [ -n "$tag_pattern" ]; then
        latest_tag=$(echo "$all_tags" | grep "$tag_pattern" | sort -rV | head -1)
    else
        latest_tag=$(echo "$all_tags" | sort -rV | head -1)
    fi
    
    if [ -n "$latest_tag" ]; then
        print_status "Latest version found: $latest_tag"
        echo "$latest_tag"
    else
        print_warning "No versions found matching pattern: $tag_pattern"
        return 1
    fi
}

# Explain Docker versioning best practices
explain_versioning_strategy() {
    echo
    print_header "🏷️  DOCKER IMAGE VERSIONING BEST PRACTICES"
    echo
    print_note "📅 DATE-BASED VERSIONING (What we use):"
    echo "  • Format: YYYY.MM.DD.HHMM-suffix (e.g., 2025.08.08.1430-s3)"
    echo "  • Immutable - each build gets unique timestamp"
    echo "  • Sortable chronologically"
    echo "  • Traceable to exact build time"
    echo
    print_note "🎯 PINNING STRATEGY (Recommended):"
    echo "  • Production: Always use specific date-based tags"
    echo "  • Development: Can use 'stable-*' aliases that point to tested versions"
    echo "  • Never use 'latest' in production deployments"
    echo
    print_note "🔍 LATEST VERSION DISCOVERY (When needed):"
    echo "  • Use find_latest_image_version() for reference only"
    echo "  • Copy the specific version tag for pinning"
    echo "  • Update .env with the pinned version"
    echo
    print_warning "❌ AVOID: Floating tags like 'latest', 'stable' in production"
    print_success "✅ USE: Specific version tags for reliable deployments"
    echo
}

# Progress indicator
show_progress() {
    local current="$1"
    local total="$2"
    local description="$3"
    
    local percentage=$((current * 100 / total))
    local bar_length=20
    local filled_length=$((current * bar_length / total))
    
    local bar=""
    for ((i=0; i<filled_length; i++)); do
        bar+="█"
    done
    for ((i=filled_length; i<bar_length; i++)); do
        bar+="░"
    done
    
    echo -e "${CYAN}[PROGRESS]${NC} [$bar] $percentage% - $description"
}

# Validate AWS CLI and credentials
check_aws_cli() {
    if ! command -v aws >/dev/null 2>&1; then
        print_error "AWS CLI is not installed"
        echo "Please install AWS CLI first:"
        echo "  curl \"https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip\" -o \"awscliv2.zip\""
        echo "  unzip awscliv2.zip"
        echo "  sudo ./aws/install"
        exit 1
    fi
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_error "AWS credentials not configured"
        echo "Please configure AWS credentials first:"
        echo "  aws configure"
        exit 1
    fi
}

# Validate Docker is running
check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        print_error "Docker is not installed"
        echo "Please install Docker first or run a script that installs it."
        exit 1
    fi
    
    if ! docker ps >/dev/null 2>&1 && ! sudo docker ps >/dev/null 2>&1; then
        print_error "Docker daemon is not running"
        echo "Please start Docker:"
        echo "  sudo systemctl start docker"
        exit 1
    fi
}

# Timeout with progress
wait_with_progress() {
    local timeout="$1"
    local check_command="$2"
    local description="$3"
    local interval="${4:-5}"
    
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        if eval "$check_command" >/dev/null 2>&1; then
            print_success "$description completed"
            return 0
        fi
        
        show_progress $elapsed $timeout "$description"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    print_error "$description timed out after $timeout seconds"
    return 1
}