#!/bin/bash
# Replace YOUR_GITHUB_USERNAME with your actual GitHub username

# Add remote origin
git remote add origin git@github.com:YOUR_GITHUB_USERNAME/smart-transcription-router.git

# Push to GitHub
git branch -M main
git push -u origin main

echo "Repository pushed to GitHub!"
echo "Don't forget to update the README with your specific configuration details."