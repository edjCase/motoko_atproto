#!/bin/bash
set -e


if [ -z "$1" ]; then
    echo "Error: network required"
    echo "Usage: $0 <network> ('new'|<plc_did>)"
    exit 1
fi

if [ -z "$2" ]; then
    echo "Error: second argument required"
    echo "Usage: $0 <network> ('new'|<plc_did>)"
    echo "  Specify 'new' to create a new DID, or provide an existing PLC DID"
    exit 1
fi

network=$1
plc_did=$2
canister_id=$(dfx canister id pds  --network "${network}")

# Map network to hostname
case "${network}" in
    local)
        hostname="${canister_id}.localhost"
        serviceSubdomain=
        serviceSubdomainCandid="null"
        fullDomain="${hostname}"
        port=":4943"
        ;;
    ic)
        hostname="edjcase.com"
        serviceSubdomain="pds"
        serviceSubdomainCandid="opt \"${serviceSubdomain}\""
        fullDomain="${serviceSubdomain}.${hostname}"
        port=""
        ;;
    *)
        echo "Error: Unsupported network '${network}'"
        echo "Supported networks: local, ic"
        exit 1
        ;;
esac

# Initialize PDS
if [ "$plc_did" = "new" ]; then
    echo "Initializing PDS in canister ${canister_id} on ${network} (${hostname}) with new DID..."
    # Create new PLC identity
    plc_variant="variant { new = record { alsoKnownAs = vec { \"at://${hostname}\" }; services = vec { record { id = \"atproto_pds\"; \"type\" = \"AtprotoPersonalDataServer\"; endpoint = \"https://${fullDomain}\" } } } }"
else
    echo "Initializing PDS in canister ${canister_id} on ${network} (${hostname}) with existing DID: ${plc_did}..."
    # Use provided PLC DID
    plc_variant="variant { id = \"${plc_did}\" }"
fi

candid_args="(record { plc = ${plc_variant}; hostname = \"${hostname}\"; serviceSubdomain = ${serviceSubdomainCandid} })"
echo "Candid args: ${candid_args}"

response=$(dfx canister call pds initialize --network "${network}" --output json "${candid_args}")

# Check for error
if echo "$response" | grep -q '"err"'; then
    error_msg=$(echo "$response" | sed -n 's/.*"err"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    echo "Error: $error_msg"
    exit 1
fi

echo "Successfully initialized PDS canister at: ${hostname}${port}"