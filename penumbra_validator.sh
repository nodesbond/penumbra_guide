#!/bin/bash

# Check for jq and install if not found
if ! command -v jq &> /dev/null; then
    echo "jq could not be found, installing now..."
    sudo apt-get update && sudo apt-get install -y jq
else
    echo "jq is already installed."
fi

# Checking the synchronization status of the node
SYNC_STATUS=$(curl -s http://0.0.0.0:26657/status | jq .result.sync_info.catching_up)
if [ "$SYNC_STATUS" = "true" ]; then
    echo "Your node is not synchronized. Please wait until it is fully synced before proceeding."
    exit 1
fi

# Changing to the Penumbra directory
cd /root/penumbra

# Creating the validator.toml file
./target/release/pcli validator definition template \
    --tendermint-validator-keyfile ~/.penumbra/testnet_data/node0/cometbft/config/priv_validator_key.json \
    --file validator.toml

# Requesting the validator's name
echo "Enter the name of your validator:"
read VALIDATOR_NAME

# Updating the validator.toml file
sed -i "s/enabled = false/enabled = true/" validator.toml
sed -i "s/name = \".*\"/name = \"$VALIDATOR_NAME\"/" validator.toml

# Uploading the validator definition
./target/release/pcli validator definition upload --file validator.toml

# Retrieving and displaying the validator identity
VALIDATOR_IDENTITY=$(./target/release/pcli validator identity)
echo "Validator identity: $VALIDATOR_IDENTITY"
