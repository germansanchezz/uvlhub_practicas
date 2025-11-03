#!/bin/bash

# ---------------------------------------------------------------------------
# Creative Commons CC BY 4.0 - David Romero - Diverso Lab
# ---------------------------------------------------------------------------
# This script syncs the uploads folder with a Git repository
# ---------------------------------------------------------------------------

set -e

UPLOADS_DIR="${WORKING_DIR}uploads"
GIT_REPO_URL="${UPLOADS_GIT_REPO_URL}"
GIT_BRANCH="${UPLOADS_GIT_BRANCH:-main}"
GIT_USER_NAME="${UPLOADS_GIT_USER_NAME:-UVLHub Bot}"
GIT_USER_EMAIL="${UPLOADS_GIT_USER_EMAIL:-bot@uvlhub.io}"

echo "Starting uploads synchronization..."

# Configure Git
git config --global user.name "$GIT_USER_NAME"
git config --global user.email "$GIT_USER_EMAIL"
git config --global credential.helper store

# Clone or pull the repository
if [ ! -d "$UPLOADS_DIR/.git" ]; then
    echo "Cloning uploads repository..."
    rm -rf "$UPLOADS_DIR"
    git clone "$GIT_REPO_URL" "$UPLOADS_DIR"
    cd "$UPLOADS_DIR"
    git checkout "$GIT_BRANCH" 2>/dev/null || git checkout -b "$GIT_BRANCH"
else
    echo "Pulling latest changes from uploads repository..."
    cd "$UPLOADS_DIR"
    git pull origin "$GIT_BRANCH" || true
fi

echo "Uploads folder synchronized successfully!"

# Start monitoring changes in background
nohup bash -c '
UPLOADS_DIR="'"$UPLOADS_DIR"'"
GIT_BRANCH="'"$GIT_BRANCH"'"

cd "$UPLOADS_DIR"

inotifywait -m -r -e modify,create,delete,move "$UPLOADS_DIR" --exclude "\.git" |
while read -r directory events filename; do
    echo "Change detected: $events $directory$filename"
    
    # Wait a bit to allow multiple changes to accumulate
    sleep 5
    
    # Add all changes
    git add -A
    
    # Check if there are changes to commit
    if ! git diff --staged --quiet; then
        TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
        git commit -m "Auto-sync uploads: $TIMESTAMP"
        
        # Push changes
        git push origin "$GIT_BRANCH" || echo "Failed to push changes"
        
        echo "Changes synchronized at $TIMESTAMP"
    fi
done
' > /tmp/uploads-sync.log 2>&1 &

echo "Background sync process started (PID: $!)"