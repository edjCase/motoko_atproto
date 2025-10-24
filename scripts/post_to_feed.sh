#!/bin/bash

if [ -z "$1" ]; then
    echo "Error: network required (local/ic)"
    echo "Usage: $0 <network> <message>"
    exit 1
fi

network=$1

canister_id=$(dfx canister id pds  --network "${network}")

if [ -z "$2" ]; then
    echo "Error: message required"
    echo "Usage: $0 <network> <message>"
    exit 1
fi

message=$2

echo "Posting '${message}' to the feed of canister ${canister_id}..."

dfx canister call ${canister_id} post "(\"${message}\")" --network "${network}"