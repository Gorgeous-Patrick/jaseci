#!/bin/bash

# HTTP API stress test for basic.jac with Redis backend
# Uses `jac start` (not --scale) to avoid K8s deployment
# Tests walker invocation via REST API under concurrent load

set -euo pipefail

REDIS_URL=${REDIS_URL:-"redis://localhost:6379"}
PORT=${PORT:-8000}
# Use unique username to avoid conflicts between runs
USERNAME="stresstest_$(date +%s%N | md5sum | cut -c1-8)"
PASSWORD=${PASSWORD:-"password123"}
NUM_REQUESTS=${NUM_REQUESTS:-50}
CONCURRENCY=${CONCURRENCY:-5}
JAC_FILE="jac/tests/language/fixtures/jac_ttg/basic.jac"

echo "=== HTTP API Stress Test for basic.jac (Redis backend) ==="
echo "REDIS_URL: ${REDIS_URL}"
echo "PORT: ${PORT}"
echo "CONCURRENCY: ${CONCURRENCY}"
echo "TOTAL_REQUESTS: ${NUM_REQUESTS}"
echo

# Start server in background
echo "Starting jac server with Redis backend..."
REDIS_URL="$REDIS_URL" \
  jac start "$JAC_FILE" --port "$PORT" > /tmp/jac_server.log 2>&1 &
SERVER_PID=$!

# Wait for server to be ready
echo "Waiting for server to start (PID: $SERVER_PID)..."
sleep 5

if ! kill -0 $SERVER_PID 2>/dev/null; then
  echo "ERROR: Server failed to start"
  cat /tmp/jac_server.log
  exit 1
fi

# Check if server is responding
for i in {1..10}; do
  if curl -s "http://localhost:$PORT/docs" > /dev/null 2>&1; then
    echo "Server is ready!"
    break
  fi
  if [ $i -eq 10 ]; then
    echo "ERROR: Server not responding after 10 attempts"
    cat /tmp/jac_server.log
    kill $SERVER_PID 2>/dev/null || true
    exit 1
  fi
  echo "Attempt $i/10: Server not ready yet..."
  sleep 1
done

trap "echo 'Shutting down server...'; kill $SERVER_PID 2>/dev/null || true; wait $SERVER_PID 2>/dev/null || true" EXIT

# Register user
echo "Registering test user: $USERNAME"
REGISTER_RESPONSE=$(curl -s -X POST "http://localhost:$PORT/user/register" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}")

TOKEN=$(echo "$REGISTER_RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('data', {}).get('token', ''))" 2>/dev/null || echo "")

if [ -z "$TOKEN" ]; then
  echo "ERROR: Failed to get authentication token"
  echo "Response: $REGISTER_RESPONSE"
  echo "Server logs:"
  tail -30 /tmp/jac_server.log
  exit 1
fi

echo "Token received: ${TOKEN:0:30}..."

# Create results directory
mkdir -p stress_test_results
RESULTS_DIR="stress_test_results/http_$(date +%s)"
mkdir -p "$RESULTS_DIR"

# Write CSV header
echo "req_id,http_code,time_ms" > "$RESULTS_DIR/results.csv"

# Concurrent request function
make_request() {
  local req_id=$1
  local start_time=$(date +%s%N)

  http_code=$(curl -s -w "%{http_code}" -o /dev/null --max-time 30 \
    -X POST "http://localhost:$PORT/walker/BFS" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{}' 2>/dev/null || echo "000")

  end_time=$(date +%s%N)
  elapsed_ms=$(( (end_time - start_time) / 1000000 ))

  echo "$req_id,$http_code,$elapsed_ms" >> "$RESULTS_DIR/results.csv"

  if [ "$http_code" != "200" ]; then
    echo "  [WARN] Request $req_id failed with code $http_code"
  fi
}

echo "Running ${NUM_REQUESTS} concurrent HTTP requests (concurrency=${CONCURRENCY})..."

# Run requests with controlled concurrency
for ((i=1; i<=NUM_REQUESTS; i++)); do
  make_request "$i" &

  # Limit concurrent jobs
  if (( i % CONCURRENCY == 0 )); then
    wait
    echo "  Completed batch: $((i - CONCURRENCY + 1))-$i"
  fi
done

# Wait for remaining jobs
wait

echo
echo "Results saved to: $RESULTS_DIR"
echo
echo "=== Summary ==="
total_requests=$(awk 'NR>1' "$RESULTS_DIR/results.csv" | wc -l)
success_count=$(awk -F',' '$2==200' "$RESULTS_DIR/results.csv" | wc -l)
failed_count=$((total_requests - success_count))

echo "Total Requests: $total_requests"
echo "Successful (200): $success_count"
echo "Failed: $failed_count"

if [ $success_count -gt 0 ]; then
  echo
  echo "Timing Stats (successful requests only):"
  awk -F',' '$2==200 {sum+=$3; count++; if(NR==2 || $3<min) min=$3; if(NR==2 || $3>max) max=$3}
    END {printf "  Average: %.2fms\n  Min: %.2fms\n  Max: %.2fms\n  Total: %.2fms\n", sum/count, min, max, sum}' \
    "$RESULTS_DIR/results.csv"
fi

echo
echo "Server logs available at: /tmp/jac_server.log"
