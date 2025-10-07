#!/bin/bash
set -e

canister_id="sctyd-5qaaa-aaaag-aa5lq-cai"
plc_id="sdpv6troz7ozrjf2titdtcd2"
hostname="edjcase.com"

echo "Deploying PDS on mainnet..."

# Deploy PDS
response=$(dfx canister call pdsFactory deployPds --ic --output json "(record { existingCanisterId = opt principal \"${canister_id}\"; kind = variant { installAndInitialize = record { plc = variant { id = \"${plc_id}\" }; hostname = \"${hostname}\"; handlePrefix = null } } })")

# Check for error
if echo "$response" | grep -q '"err"'; then
    error_msg=$(echo "$response" | sed -n 's/.*"err"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    echo "Error: $error_msg"
    exit 1
fi


echo "Successfully deployed and initialized PDS canister with ID: $canister_id"
