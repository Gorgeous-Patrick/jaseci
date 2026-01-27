#!/bin/bash

# HTTP API stress test for basic.jac
# Tests walker invocation via REST API under concurrent load
# NOTE: Start the server manually before running this script

set -euo pipefail

PORT=${PORT:-8000}
# Use unique username to avoid conflicts between runs
USERNAME="stresstest_$(date +%s%N | md5sum | cut -c1-8)"
PASSWORD=${PASSWORD:-"password123"}
NUM_REQUESTS=${NUM_REQUESTS:-50}
CONCURRENCY=${CONCURRENCY:-5}

echo "=== HTTP API Stress Test for basic.jac ==="
echo "PORT: ${PORT}"
echo "CONCURRENCY: ${CONCURRENCY}"
echo "TOTAL_REQUESTS: ${NUM_REQUESTS}"
echo

# Check if server is responding
echo "Checking if server is running on port $PORT..."
for i in {1..5}; do
  if curl -s "http://localhost:$PORT/docs" > /dev/null 2>&1; then
    echo "✓ Server is ready!"
    break
  fi
  if [ $i -eq 5 ]; then
    echo "✗ ERROR: Server not responding at http://localhost:$PORT"
    echo "Start the server first:"
    echo "  REDIS_URL=redis://localhost:6379 jac start jac/tests/language/fixtures/jac_ttg/basic.jac --port $PORT"
    exit 1
  fi
  echo "  Attempt $i/5..."
  sleep 1
done

# Register user
echo "Registering test user: $USERNAME"
REGISTER_RESPONSE=$(curl -s -X POST "http://localhost:$PORT/user/register" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}")

TOKEN=$(echo "$REGISTER_RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('data', {}).get('token', ''))" 2>/dev/null || echo "")

if [ -z "$TOKEN" ]; then
  echo "ERROR: Failed to get authentication token"
  echo "Response: $REGISTER_RESPONSE"
  exit 1
fi

echo "✓ Token received: ${TOKEN:0:30}..."

# Create nodes and get their IDs
echo "Creating nodes via create_node function..."
CREATE_RESPONSE=$(curl -s -X POST "http://localhost:$PORT/function/create_node" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}')

echo $CREATE_RESPONSE

NODE_IDS=$(echo "$CREATE_RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin).get('data', {}).get('result', []); print(' '.join(data))" 2>/dev/null || echo "")

if [ -z "$NODE_IDS" ]; then
  echo "ERROR: Failed to create nodes"
  echo "Response: $CREATE_RESPONSE"
  exit 1
fi

# Convert to array
NODE_IDS_ARRAY=($NODE_IDS)
echo "✓ Created ${#NODE_IDS_ARRAY[@]} nodes"
echo "  First node ID: ${NODE_IDS_ARRAY[0]:0:30}..."

# Create results directory
mkdir -p stress_test_results
RESULTS_DIR="stress_test_results/http_$(date +%s)"
mkdir -p "$RESULTS_DIR"

# Write CSV header
echo "req_id,node_id,http_code,time_ms" > "$RESULTS_DIR/results.csv"

# Concurrent request function - spawn walker on specific node
make_request() {
  local req_id=$1
  local node_id=$2
  local start_time=$(date +%s%N)

  response=$(curl -s -w "\n%{http_code}" --max-time 30 \
    -X POST "http://localhost:$PORT/walker/BFS/$node_id" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{}" 2>/dev/null || echo "\n000")

  http_code=$(echo "$response" | tail -1)
  response_body=$(echo "$response" | sed '$d')

  end_time=$(date +%s%N)
  elapsed_ms=$(( (end_time - start_time) / 1000000 ))

  echo "$req_id,${node_id:0:8}...,$http_code,$elapsed_ms" >> "$RESULTS_DIR/results.csv"

  if [ "$http_code" != "200" ]; then
    echo "  [WARN] Request $req_id (node ${node_id:0:8}...) failed with code $http_code"
    if [ -n "$response_body" ]; then
      echo "  [WARN] Response: $response_body"
    fi
  fi
}

echo "Spawning walker on each of the ${#NODE_IDS_ARRAY[@]} nodes..."

# Spawn one walker per node (ignore NUM_REQUESTS, just use actual nodes)
for ((i=0; i<${#NODE_IDS_ARRAY[@]}; i++)); do
  node_id="${NODE_IDS_ARRAY[$i]}"
  req_id=$((i + 1))

  make_request "$req_id" "$node_id" &

  # Limit concurrent jobs
  if (( (i + 1) % CONCURRENCY == 0 )); then
    wait
    echo "  Completed batch: $((i - CONCURRENCY + 2))-$((i + 1))"
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
