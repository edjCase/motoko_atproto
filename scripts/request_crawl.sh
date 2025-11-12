#!/bin/bash
set -e

hostname="pds2.edjcase.com"
relay="https://bsky.network"

echo "Requesting crawl from ${relay} for ${hostname}..."
echo ""

response=$(curl -X POST "${relay}/xrpc/com.atproto.sync.requestCrawl" \
    -H "Content-Type: application/json" \
    -d "{\"hostname\": \"${hostname}\"}" \
    -w "\n--- HTTP Status: %{http_code} ---\n" \
    --fail-with-body \
    2>&1) || true

echo "${response}"
echo ""

if echo "${response}" | grep -q "HTTP Status: 200"; then
    echo "✓ Crawl request successful"
    exit 0
else
    echo "✗ Crawl request failed"
    exit 1
fi