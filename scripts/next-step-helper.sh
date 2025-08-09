#!/bin/bash

# next-step-helper.sh - Generic function to automatically determine next script in sequence

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to show the next step in the sequence
show_next_step() {
    local current_script="$1"
    local script_dir="$2"
    
    # Default to current directory if script_dir not provided
    if [ -z "$script_dir" ]; then
        script_dir="$(dirname "$0")"
    fi
    
    # Get just the filename without path
    local current_filename=$(basename "$current_script")
    
    # Get the current script number
    local current_number=$(echo "$current_filename" | grep -o 'step-[0-9]\+' | grep -o '[0-9]\+')
    
    # Find all step scripts, sorted numerically by step number
    # Use find to get full paths, then sort by numerical step number
    local all_scripts_raw=$(find "$script_dir" -name "step-*.sh" -type f 2>/dev/null)
    
    # Sort by extracting step number and sorting numerically
    local all_scripts=""
    while IFS= read -r script; do
        if [[ -n "$script" ]]; then
            all_scripts="$all_scripts$script"$'\n'
        fi
    done < <(echo "$all_scripts_raw" | sort -t'-' -k2 -n)
    
    # Remove the last newline
    all_scripts=$(echo "$all_scripts" | sed '$d')
    
    # Find the current script position
    local found_current=false
    local next_script=""
    
    # Convert to array for easier iteration
    while IFS= read -r script; do
        if [[ -z "$script" ]]; then continue; fi
        
        local script_name=$(basename "$script")
        
        if [ "$found_current" = true ]; then
            # Skip divider files (contain "=-=-=-=-=") and step-navigation.sh
            if [[ "$script_name" != *"=-=-=-=-="* ]] && [[ "$script_name" != "step-navigation.sh" ]]; then
                next_script="$script"
                break
            fi
        fi
        
        if [ "$script_name" = "$current_filename" ]; then
            found_current=true
        fi
    done <<< "$all_scripts"
    
    echo ""
    echo -e "${GREEN}======================================${NC}"
    echo -e "${GREEN}🎯 NEXT STEP${NC}"
    echo -e "${GREEN}======================================${NC}"
    
    if [ -n "$next_script" ]; then
        local next_name=$(basename "$next_script")
        # Show path relative to current working directory
        local current_dir=$(basename "$(pwd)")
        if [[ "$current_dir" != "scripts" ]]; then
            echo -e "${BLUE}Run:${NC} ./scripts/$next_name"
        else
            echo -e "${BLUE}Run:${NC} ./$next_name"
        fi
        
        # Try to get a description from the script header
        local description=$(head -5 "$next_script" 2>/dev/null | grep -E '^#.*-.*' | head -1 | sed 's/^#[[:space:]]*//' | sed 's/step-[0-9]*-[^[:space:]]*//' | sed 's/^[[:space:]]*//')
        if [ -n "$description" ]; then
            echo -e "${CYAN}Purpose:${NC} $description"
        fi
    else
        # Check if we're at a series boundary or end of scripts
        local series_300_start=$(ls "$script_dir"/step-3*.sh 2>/dev/null | head -1)
        if [ -n "$current_number" ] && [ "$current_number" -lt "300" ] && [ -n "$series_300_start" ]; then
            echo "   ✅ Initial setup complete! Continue with Fast API deployment:"
            echo -e "   ${BLUE}Run:${NC} ./scripts/$(basename "$series_300_start")"
        else
            echo "   ✅ All steps complete! Your transcription system is ready."
        fi
    fi
    echo ""
}

# Function to show the current series overview
show_series_overview() {
    local current_script="$1"
    local script_dir="$2"
    
    # Default to current directory if script_dir not provided
    if [ -z "$script_dir" ]; then
        script_dir="$(dirname "$0")"
    fi
    
    local current_filename=$(basename "$current_script")
    local current_series=$(echo "$current_filename" | grep -o 'step-[0-9]\+' | grep -o '[0-9]\+')
    local series_prefix="${current_series:0:1}00"
    
    echo ""
    echo "📊 CURRENT SERIES OVERVIEW:"
    
    # Get series name from divider file
    local divider_file=$(ls "$script_dir"/step-${series_prefix:0:1}*=-=-=-=-*.sh 2>/dev/null | head -1)
    if [ -n "$divider_file" ]; then
        local series_name=$(basename "$divider_file" | sed 's/step-[0-9]*-=-=-=-=-=//' | sed 's/=-=-=--=-=-.sh//' | tr '-' ' ')
        echo "   🏷️  PATH ${series_prefix:0:1}00: $series_name"
    fi
    
    # Show all scripts in series with status
    local all_scripts=$(ls "$script_dir"/step-${series_prefix:0:1}*.sh 2>/dev/null | grep -v "=-=-=-=-=" | sort)
    local current_reached=false
    
    for script in $all_scripts; do
        local script_name=$(basename "$script")
        local step_num=$(echo "$script_name" | grep -o 'step-[0-9]\+' | grep -o '[0-9]\+')
        
        if [ "$script_name" = "$current_filename" ]; then
            echo "   ➤  $script_name (CURRENT)"
            current_reached=true
        elif [ "$current_reached" = false ]; then
            echo "   ✅ $script_name"
        else
            echo "   ⏳ $script_name"
        fi
    done
    echo ""
}

# Note: Auto-detection removed to prevent duplicate calls
# Scripts should manually call: show_next_step "$0" "$(dirname "$0")"