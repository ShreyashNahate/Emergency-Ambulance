#!/bin/bash

# Go to the project folder
cd /Users/shreyashnahate/Vs_Code/flutter/ambulence || exit

# Pull remote changes first (rebase to avoid merge commits)
git pull origin main --rebase || echo "No remote changes or already up to date"

# Stage all changes in the current folder
git add .

# Commit with date stamp, skip if nothing to commit
git commit -m "Daily auto commit from ambulence on $(date)" || echo "No changes to commit"

# Push to remote
git push origin main || echo "Push failed, check manually"

