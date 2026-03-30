#!/usr/bin/env python3
"""Save group contexts from session history."""

import json
import os
from datetime import datetime, timedelta

# Load groups index
index_path = "/home/gorcer/.openclaw/workspace/groups/index.md"
groups_dir = "/home/gorcer/.openclaw/workspace/groups"

def load_index():
    """Parse groups/index.md to get chat_id → slug mapping."""
    with open(index_path, 'r') as f:
        content = f.read()
    
    mapping = {}
    for line in content.split('\n'):
        if line.startswith('-') and '→' in line:
            parts = line.split('→')
            chat_id = parts[0].strip().lstrip('-')
            slug = parts[1].strip()
            mapping[chat_id] = slug
    return mapping

def get_group_key(chat_id):
    """Get group key from chat_id for sessions_history."""
    # Telegram group IDs are negative
    return f"telegram:-{chat_id}"

def main():
    print(f"[{datetime.now().isoformat()}] Starting group context save...")
    
    mapping = load_index()
    print(f"Found {len(mapping)} groups: {mapping}")
    
    # For now, just log - actual session history reading happens in agent
    for chat_id, slug in mapping.items():
        print(f"  Would save context for {slug} (chat_id: {chat_id})")
    
    print("Done. Context save triggered.")

if __name__ == "__main__":
    main()
