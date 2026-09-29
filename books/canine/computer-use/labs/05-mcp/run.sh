#!/usr/bin/env bash
# Lab 5 walkthrough: the same server, reached the way Claude Code reaches it: through Canine's MCP tools, which check
# who you are, open a port-forward, and turn replies into MCP content (screenshots become images). Clicks nothing.
source "$(dirname "$0")/../env.sh"
cd "$(dirname "$0")"
tools() { (cd "$CANINE_DIR" && bin/rails runner "$LABS/05-mcp/mcp_tools.rb" "$COMPUTER_ID" "$1" 2>&1 | grep -v faraday-retry); }

step "1. The four tools Canine's /mcp endpoint offers for agent computers, and what they take"
run tools schemas
note "computer_action's inputs are the fields of Anthropic's computer-use tool, so a model's action passes straight through."

step "2. Call them as the computer's owner, and time each call"
run tools calls
note "Every call looks up the VM's pod (~1s) and opens a fresh kubectl port-forward (~1.5s) before the action runs."
note "Screenshots come back as MCP image content, so Claude sees the picture, plus the size as text."
