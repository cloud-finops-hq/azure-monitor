#!/bin/bash
# Start Azure Cost Dashboard
# Port 8847 - unique port to avoid conflicts with common dev ports

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT=8847

echo "Azure Cost Dashboard"
echo "===================="

# Kill any existing server on this port
lsof -ti:$PORT | xargs kill -9 2>/dev/null || true

# Collect fresh data
echo "Collecting Azure data..."
"$SCRIPT_DIR/collect-data.sh" > /dev/null 2>&1

# Start server
echo "Starting dashboard on port $PORT..."
cd "$SCRIPT_DIR"
python3 -m http.server $PORT &
SERVER_PID=$!

sleep 1

# Open in browser
echo "Opening http://localhost:$PORT"
open "http://localhost:$PORT" 2>/dev/null || xdg-open "http://localhost:$PORT" 2>/dev/null || echo "Open http://localhost:$PORT in your browser"

echo ""
echo "Dashboard running (PID: $SERVER_PID)"
echo "Press Ctrl+C to stop"

# Wait for Ctrl+C
trap "kill $SERVER_PID 2>/dev/null; echo 'Dashboard stopped.'; exit 0" INT
wait $SERVER_PID
