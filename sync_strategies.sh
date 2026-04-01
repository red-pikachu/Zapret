#!/bin/bash
# Sync & Push Zapret2Mac Strategies to GitHub
# Usage: ./sync_strategies.sh "Comment about the update"

STRATEGIES_FILE="strategies.json"
REMOTE_REPO="https://github.com/red-pikachu/Zapret2Mac.git"

if [ ! -f "$STRATEGIES_FILE" ]; then
    echo "Error: $STRATEGIES_FILE not found."
    exit 1
fi

COMMIT_MSG=${1:-"Update bypass strategies"}

echo "--- Syncing Strategies ---"
git add "$STRATEGIES_FILE"
git commit -m "$COMMIT_MSG"
git push origin main

echo "Done! Strategies pushed to GitHub."
echo "The App will now automatically pull these updates on next launch or via 'Update Strategies' menu."
