#!/bin/bash

if [ -z "$1" ]; then
    echo "Error: canisterId required"
    echo "Usage: $0 <canisterId>"
    exit 1
fi

canister_id=$1

echo "Upgrading canister: $canister_id"

dfx canister call pdsFactory upgrade "(principal \"${canister_id}\")"

echo "Upgrade complete"