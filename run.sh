set -euo pipefail
if [ -f "timer.json" ]; then
  rm timer.json
fi
if [ -f "cache_stats.json" ]; then
  rm cache_stats.json
fi


# ====== Configurable parameters ======
NODE_NUM=${NODE_NUM:-250}         # number of nodes (can override: NODE_NUM=100 ./sweep.sh)
STEP=${STEP:-250}                   # edge step size      (override: STEP=10 ./sweep.sh)
TWEET_NUM=${TWEET_NUM:-1}         # JAC_TWEET_NUM
CACHE_SIZE=${CACHE_SIZE:-10}      # JAC_CACHE_SIZE for walker cache
JAC_FILE=${JAC_FILE:-jac/tests/language/fixtures/jac_ttg/littlex2.jac}
# =====================================

# Fully connected directed graph (no self-loops):
# max_edges = N * (N - 1)
MAX_EDGES=$(( NODE_NUM * (NODE_NUM - 1) ))

echo "Sweeping graph density:"
echo "  NODE_NUM  = ${NODE_NUM}"
echo "  STEP      = ${STEP}"
echo "  MAX_EDGES = ${MAX_EDGES}"
echo "  JAC_FILE  = ${JAC_FILE}"
echo

for (( edges=0; edges<=MAX_EDGES; edges+=STEP )); do
    echo "Running with JAC_NODE_NUM=${NODE_NUM}, JAC_EDGE_NUM=${edges}, JAC_TWEET_NUM=${TWEET_NUM}"

    JAC_NODE_NUM="${NODE_NUM}" \
    JAC_EDGE_NUM="${edges}" \
    JAC_TWEET_NUM="${TWEET_NUM}" \
    JAC_CACHE_SIZE="${CACHE_SIZE}" \
        jac run "${JAC_FILE}"  --no-cache > out.txt

    echo "------------------------------------------------------"
done
