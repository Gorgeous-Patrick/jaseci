#!/bin/bash

# Stress test runner script
# - Reads token and node IDs from setup file
# - Spawns walkers on each node

set -euo pipefail

SETUP_FILE=${SETUP_FILE:-"stress_test_data.json"}
CONCURRENCY=${CONCURRENCY:-5}

echo "=== HTTP API Stress Test Runner ==="
echo "SETUP_FILE: $SETUP_FILE"
echo "CONCURRENCY: $CONCURRENCY"
echo

# Load setup data
if [ ! -f "$SETUP_FILE" ]; then
  echo "ERROR: Setup file not found: $SETUP_FILE"
  echo "Run setup first: ./stress_test_setup.sh"
  exit 1
fi

echo "Loading setup data from $SETUP_FILE..."
PORT=$(python3 -c "import json; print(json.load(open('$SETUP_FILE'))['port'])")
TOKEN=$(python3 -c "import json; print(json.load(open('$SETUP_FILE'))['token'])")
NODE_IDS_JSON=$(python3 -c "import json; print(json.dumps(json.load(open('$SETUP_FILE'))['node_ids']))")

NODE_IDS_ARRAY=($(python3 -c "import json; print(' '.join(json.loads('$NODE_IDS_JSON')))"))
echo "✓ Loaded config"
echo "  Port: $PORT"
echo "  Token: ${TOKEN:0:30}..."
echo "  Nodes: ${#NODE_IDS_ARRAY[@]}"
echo

# Check if server is still responding
echo "Checking if server is still running..."
if ! curl -s "http://localhost:$PORT/docs" > /dev/null 2>&1; then
  echo "ERROR: Server not responding at http://localhost:$PORT"
  exit 1
fi
echo "✓ Server is ready!"

# Create results directory
mkdir -p stress_test_results
RESULTS_DIR="stress_test_results/run_$(date +%s)"
mkdir -p "$RESULTS_DIR"

# Write CSV header
echo "req_id,node_id,http_code,time_ms" > "$RESULTS_DIR/results.csv"
# Track raw HTTP codes from curl
> "$RESULTS_DIR/http_codes.log"

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
  echo "$http_code" >> "$RESULTS_DIR/http_codes.log"

  if [ "$http_code" != "200" ]; then
    echo "  [WARN] Request $req_id (node ${node_id:0:8}...) failed with code $http_code"
    if [ -n "$response_body" ]; then
      echo "  [WARN] Response: $response_body"
    fi
  fi
}

echo "Spawning walker on each of the ${#NODE_IDS_ARRAY[@]} nodes..."

# Spawn one walker per node
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
total_requests=$(wc -l < "$RESULTS_DIR/http_codes.log")
success_count=$(grep -c '^200$' "$RESULTS_DIR/http_codes.log" || true)
failed_count=$((total_requests - success_count))

echo "Total Requests: $total_requests"
echo "Successful (200): $success_count"
echo "Failed: $failed_count"

if [ $success_count -gt 0 ]; then
  success_rate=$((success_count * 100 / total_requests))
  echo "Success Rate: $success_rate%"

  echo
  echo "Timing Stats (successful requests only):"
  awk -F',' '$3==200 {sum+=$4; count++; if(NR==2 || $4<min) min=$4; if(NR==2 || $4>max) max=$4}
    END {if(count>0) printf "  Average: %.2fms\n  Min: %.2fms\n  Max: %.2fms\n  Total: %.2fms\n", sum/count, min, max, sum}' \
    "$RESULTS_DIR/results.csv"
fi

echo
echo "To run stress test again:"
echo "  ./stress_test_run.sh"
echo
echo "To setup new nodes:"
echo "  ./stress_test_setup.sh"
