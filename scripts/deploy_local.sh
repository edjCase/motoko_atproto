#!/bin/bash
set -e

echo "Deploying PDS locally..."

# Deploy PDS
response=$(dfx canister call pdsFactory deployPds --output json '(record { existingCanisterId = null; kind = variant { installOnly } })')

# Check for error
if echo "$response" | grep -q '"err"'; then
    error_msg=$(echo "$response" | sed -n 's/.*"err"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    echo "Error: $error_msg"
    exit 1
fi

# Extract canister ID
canister_id=$(echo "$response" | sed -n 's/.*"ok"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

echo "Successfully deployed PDS canister with ID: $canister_id"

echo "Initializing PDS..."

# Initialize PDS
response=$(dfx canister call pdsFactory initializePds --output json "(principal \"${canister_id}\", record { plc = variant { id = \"sdpv6troz7ozrjf2titdtcd2\" }; hostname = \"${canister_id}.localhost\"; handlePrefix = null })")

# Check for error
if echo "$response" | grep -q '"err"'; then
    error_msg=$(echo "$response" | sed -n 's/.*"err"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    echo "Error: $error_msg"
    exit 1
fi

echo "Successfully initialized PDS canister at: ${canister_id}.localhost:4943"