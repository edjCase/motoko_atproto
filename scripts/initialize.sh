#!/bin/bash
set -e

canister_id=$(dfx canister id pds)

echo "Initializing PDS in canister ${canister_id}..."


# Initialize PDS
response=$(dfx canister call pds initialize --output json "(record { plc = variant { id = \"sdpv6troz7ozrjf2titdtcd2\" }; hostname = \"${canister_id}.localhost\"; handlePrefix = null })")

# Check for error
if echo "$response" | grep -q '"err"'; then
    error_msg=$(echo "$response" | sed -n 's/.*"err"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    echo "Error: $error_msg"
    exit 1
fi

echo "Successfully initialized PDS canister at: ${canister_id}.localhost:4943"