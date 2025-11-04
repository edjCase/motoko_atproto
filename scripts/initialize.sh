#!/bin/bash
set -e


if [ -z "$1" ]; then
    echo "Error: network required"
    echo "Usage: $0 <network> <mode>"
    exit 1
fi

network=$1

canister_id=$(dfx canister id pds  --network "${network}")

# Map network to hostname
case "${network}" in
    local)
        hostname="${canister_id}.localhost"
        serviceSubdomain="null"
        port=":4943"
        ;;
    ic)
        hostname="edjcase.com"
        serviceSubdomain="opt \"pds\""
        port=""
        ;;
    *)
        echo "Error: Unsupported network '${network}'"
        echo "Supported networks: local, ic"
        exit 1
        ;;
esac

echo "Initializing PDS in canister ${canister_id} on ${network} (${hostname})..."

# Initialize PDS
response=$(dfx canister call pds initialize --network "${network}" --output json "(record { plc = variant { id = \"sdpv6troz7ozrjf2titdtcd2\" }; hostname = \"${hostname}\"; serviceSubdomain = ${serviceSubdomain} })")

# Check for error
if echo "$response" | grep -q '"err"'; then
    error_msg=$(echo "$response" | sed -n 's/.*"err"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    echo "Error: $error_msg"
    exit 1
fi

echo "Successfully initialized PDS canister at: ${hostname}${port}"