#!/bin/bash
set -e

if [ -z "$1" ]; then
    echo "Error: network required"
    echo "Usage: $0 <network> <mode>"
    exit 1
fi


if [ -z "$2" ]; then
    mode="auto"
else
    mode=$2
fi


network=$1

echo "Deploying PDS to network '${network}' and using mode '${mode}'..."


# Deploy PDS
response=$(dfx deploy pds --argument-type idl --argument "(record { owner = null })" --network "${network}" --mode "${mode}")

echo "$response"

# Extract canister ID
canister_id=$(dfx canister id pds --network "${network}" )

echo "Successfully deployed PDS canister with ID: $canister_id"