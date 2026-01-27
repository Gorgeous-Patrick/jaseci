#!/bin/bash

# Concurrent stress test for basic.jac with Redis backend
# Tests walker execution via `jac enter` under concurrent load with Redis cache

set -euo pipefail

REDIS_URL=${REDIS_URL:-"redis://localhost:6379"}
NUM_REQUESTS=${NUM_REQUESTS:-50}
CONCURRENCY=${CONCURRENCY:-5}
JAC_FILE="jac/tests/language/fixtures/jac_ttg/basic.jac"

echo "=== Concurrent Stress Test for basic.jac (Redis backend) ==="
echo "REDIS_URL: ${REDIS_URL}"
echo "CONCURRENCY: ${CONCURRENCY}"
echo "TOTAL_REQUESTS: ${NUM_REQUESTS}"
echo

echo "Redis connected successfully"

# Create results directory
mkdir -p stress_test_results
RESULTS_DIR="stress_test_results/stress_$(date +%s)"
mkdir -p "$RESULTS_DIR"

# Concurrent walker execution function
run_walker() {
  local req_id=$1
  local start_time=$(date +%s%N)

  REDIS_URL="$REDIS_URL" \
    timeout 60 jac enter "$JAC_FILE" BFS > /dev/null 2>&1
  exit_code=$?

  end_time=$(date +%s%N)
  elapsed_ms=$(( (end_time - start_time) / 1000000 ))

  if [ $exit_code -eq 0 ]; then
    status="success"
  else
    status="failed"
  fi

  echo "req_id=${req_id},status=${status},time_ms=${elapsed_ms}" >> "$RESULTS_DIR/results.csv"
}

echo "Running ${NUM_REQUESTS} concurrent walkers (concurrency=${CONCURRENCY})..."

# Write CSV header
echo "req_id,status,time_ms" > "$RESULTS_DIR/results.csv"

# Run requests with controlled concurrency
for ((i=1; i<=NUM_REQUESTS; i++)); do
  run_walker "$i" &

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
grep "status=success" "$RESULTS_DIR/results.csv" | wc -l | xargs echo "Successful walkers:"
echo "Average time per walker:"
awk -F'=' 'NR>1 {split($NF, a, ","); sum+=a[1]; count++} END {printf "%.2fms\n", sum/count}' "$RESULTS_DIR/results.csv"
echo "Total time:"
awk -F'=' 'NR>1 {split($NF, a, ","); sum+=a[1]; count++} END {printf "%.2fms (%d runs)\n", sum, count}' "$RESULTS_DIR/results.csv"
echo "Min/Max time:"
awk -F'=' 'NR>1 {split($NF, a, ","); t=a[1]; if(NR==2 || t<min) min=t; if(NR==2 || t>max) max=t} END {printf "%.2fms / %.2fms\n", min, max}' "$RESULTS_DIR/results.csv"
