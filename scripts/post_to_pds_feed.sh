#!/bin/bash

if [ -z "$1" ]; then
    echo "Error: canisterId required"
    echo "Usage: $0 <canisterId> <message>"
    exit 1
fi

if [ -z "$2" ]; then
    echo "Error: message required"
    echo "Usage: $0 <canisterId> <message>"
    exit 1
fi

canister_id=$1
message=$2

dfx canister call ${canister_id} post "(\"${message}\")"