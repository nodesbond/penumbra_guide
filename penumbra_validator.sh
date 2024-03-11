#!/bin/bash

# Check for jq and install if not found
if ! command -v jq &> /dev/null; then
    echo "jq could not be found, installing now..."
    sudo apt-get update && sudo apt-get install -y jq
else
    echo "jq is already installed."
fi

# Attempt to automatically determine the server's public IP address
IP_ADDRESS=$(curl -4s ifconfig.me)

# If automatic IP detection fails, prompt for manual input
if [ -z "$IP_ADDRESS" ]; then
    echo "Could not automatically determine the server's IP address."
    echo "Please enter the server's external IP address manually:"
    read IP_ADDRESS
fi

# Validate the IP_ADDRESS input
if [[ ! $IP_ADDRESS =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid IP address format. Exiting."
    exit 1
fi

# Checking the synchronization status of the node using the IP address
SYNC_STATUS=$(curl -s http://$IP_ADDRESS:26657/status | jq -r .result.sync_info.catching_up)

if [ "$SYNC_STATUS" = "true" ]; then
    echo "Your node is not synchronized. Please wait until it is fully synced before proceeding."
    exit 1
else
    echo "Node is synchronized. Continuing with validator setup."
fi

# Creating the validator.toml file
pcli validator definition template \
    --tendermint-validator-keyfile ~/.penumbra/testnet_data/node0/cometbft/config/priv_validator_key.json \
    --file validator.toml

# Requesting the validator's name
echo "Enter the name of your validator:"
read VALIDATOR_NAME

# Updating the validator.toml file
sed -i "s/enabled = false/enabled = true/" validator.toml
sed -i "s/name = \".*\"/name = \"$VALIDATOR_NAME\"/" validator.toml

# Uploading the validator definition
pcli validator definition upload --file validator.toml

# Retrieving and displaying the validator identity
VALIDATOR_IDENTITY=$(pcli validator identity)
echo "Validator identity: $VALIDATOR_IDENTITY"
