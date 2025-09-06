#!/bin/bash

LEXICONS_DIR="lexicons"
REPO_URL="https://github.com/bluesky-social/atproto.git"

if [ -d "$LEXICONS_DIR" ]; then
    echo "Updating lexicons..."
    cd "$LEXICONS_DIR"
    git pull origin main
    cd ..
else
    echo "Initializing lexicons..."
    git clone --filter=blob:none --no-checkout --depth 1 --sparse "$REPO_URL" "$LEXICONS_DIR"
    cd "$LEXICONS_DIR"
    git sparse-checkout set lexicons
    git checkout main
    cd ..
    # Move lexicon files up one level
    mv "$LEXICONS_DIR/lexicons/"* "$LEXICONS_DIR/"
    rm -rf "$LEXICONS_DIR/.git" "$LEXICONS_DIR/lexicons"
fi

echo "Done."