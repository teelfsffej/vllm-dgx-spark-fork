#!/usr/bin/env bash
set -euo pipefail

# Directory handling
cd "$(dirname "$0")/.."  # repo root

# Build the Docker image (uses the existing Dockerfile which already includes patches)
REGISTRY="registry.mycorp.com"
TAG="vllm-node-mxfp4:patched-$(date +%Y%m%d%H%M)"
FULL_TAG="${REGISTRY}/${TAG}"

echo "Building Docker image $FULL_TAG..."

docker build -t "${FULL_TAG}" .

# Push to the registry (requires docker login beforehand)
if docker push "${FULL_TAG}"; then
  echo "Image pushed successfully."
else
  echo "Push failed – you may need to login to the registry."
  exit 1
fi

# Smoke‑test: run a temporary container and issue a simple VLLM request
PORT=8000
CONTAINER_NAME="vllm_test_$(date +%s)"

echo "Starting test container..."
# Run in detached mode, expose port 8000
docker run -d --name "$CONTAINER_NAME" -p ${PORT}:80 "$FULL_TAG"

# Give the service a moment to start (adjust as needed)
sleep 10

# Simple health‑check – request the VLLM health endpoint (if available)
if curl -s http://localhost:${PORT}/health; then
  echo "Health check passed."
else
  echo "Health check failed – container may not be ready."
fi

# Minimal inference test (adjust to your endpoint path if different)
cat <<'PY' > /tmp/test_prompt.py
import requests, json
payload = {"model":"gpt-oss-120b","prompt":"Hello","max_tokens":5}
resp = requests.post('http://localhost:${PORT}/v1/completions', json=payload)
print(json.dumps(resp.json(), indent=2))
PY
python3 /tmp/test_prompt.py > verify.log

# Cleanup
docker rm -f "$CONTAINER_NAME"

echo "Verification log written to verify.log"
