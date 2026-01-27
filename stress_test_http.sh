#!/bin/bash

# HTTP API stress test for basic.jac - uses jac start --scale
# Tests walker invocation via REST API under concurrent load

set -euo pipefail

REDIS_URL=${REDIS_URL:-"redis://localhost:6379"}
MONGODB_URI=${MONGODB_URI:-""}
PORT=${PORT:-8000}
USERNAME=${USERNAME:-"stresstest"}
PASSWORD=${PASSWORD:-"password123"}
NUM_REQUESTS=${NUM_REQUESTS:-50}
CONCURRENCY=${CONCURRENCY:-5}
JAC_FILE="jac/tests/language/fixtures/jac_ttg/basic.jac"

echo "=== HTTP API Stress Test for basic.jac ==="
echo "PORT: ${PORT}"
echo "CONCURRENCY: ${CONCURRENCY}"
echo "TOTAL_REQUESTS: ${NUM_REQUESTS}"
echo

# Start server in background
echo "Starting jac scale server..."
REDIS_URL="$REDIS_URL" MONGODB_URI="$MONGODB_URI" \
  jac start --scale "$JAC_FILE" --port "$PORT" > /tmp/jac_server.log 2>&1 &
SERVER_PID=$!

# Wait for server to be ready
sleep 3
if ! kill -0 $SERVER_PID 2>/dev/null; then
  echo "ERROR: Server failed to start"
  cat /tmp/jac_server.log
  exit 1
fi

trap "kill $SERVER_PID 2>/dev/null || true" EXIT

echo "Server started (PID: $SERVER_PID)"

# Register user
echo "Registering test user..."
TOKEN=$(curl -s -X POST "http://localhost:$PORT/user/register" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}" \
  | python3 -c "import sys, json; print(json.load(sys.stdin)['data'].get('token', ''))" 2>/dev/null || echo "")

if [ -z "$TOKEN" ]; then
  echo "ERROR: Failed to get authentication token"
  echo "Server logs:"
  tail -20 /tmp/jac_server.log
  exit 1
fi

echo "Token: ${TOKEN:0:20}..."

# Create results directory
mkdir -p stress_test_results
RESULTS_DIR="stress_test_results/http_$(date +%s)"
mkdir -p "$RESULTS_DIR"

# Concurrent request function
make_request() {
  local req_id=$1
  local start_time=$(date +%s%N)

  response=$(curl -s -w "\n%{http_code}" \
    -X POST "http://localhost:$PORT/walker/BFS" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{}' 2>/dev/null || echo "500")

  http_code=$(echo "$response" | tail -1)
  end_time=$(date +%s%N)
  elapsed_ms=$(( (end_time - start_time) / 1000000 ))

  echo "req_id=${req_id},http_code=${http_code},time_ms=${elapsed_ms}" >> "$RESULTS_DIR/results.csv"
}

echo "Running ${NUM_REQUESTS} concurrent requests (concurrency=${CONCURRENCY})..."

# Run requests with controlled concurrency
for ((i=1; i<=NUM_REQUESTS; i++)); do
  make_request "$i" &

  # Limit concurrent jobs
  if (( i % CONCURRENCY == 0 )); then
    wait
  fi
done

# Wait for remaining jobs
wait

echo
echo "Results saved to: $RESULTS_DIR"
echo "Summary:"
grep "http_code=200" "$RESULTS_DIR/results.csv" | wc -l | xargs echo "Successful requests:"
tail -10 "$RESULTS_DIR/results.csv"
