#!/bin/bash

# Author: WhisperNode
# Penumbra Version: v0.69.0
# Go Version: 1.21.1
# Cometbft Version: v0.37.2

#Stop Current Services
sudo systemctl stop penumbra
sudo systemctl stop cometbft

# Check Ubuntu Version
UBUNTU_VERSION=$(lsb_release -sr)
if (( $(echo "$UBUNTU_VERSION < 22" | bc -l) )); then
    echo "This script requires Ubuntu version 22 or higher. Your version is $UBUNTU_VERSION."
    exit 1
fi

#Copy Old keys and config file
echo "Copying old config..."
cd /home/whispernode/.penumbra/testnet_data/node0/cometbft/config
sudo cp config.toml /home/whispernode/penumbraconfig.toml

# Remove previous versions of Penumbra and related modules
echo "Removing old versions of Penumbra and related modules..."
cd /home/whispernode
sudo rm -rf /home/whispernode/penumbra /home/whispernode/cometbft /home/whispernode/.local/share/pcli/ /home/whispernode/.penumbra

# Update package list and install dependencies
sudo apt-get update
sudo apt-get install -y build-essential pkg-config libssl-dev clang git-lfs tmux libclang-dev curl
sudo apt-get install tmux

# Check if Go is installed and update it if it is not version 1.21.1
CURRENT_GO_VERSION=$(go version | grep -oP 'go\K[0-9.]+')
if [ "$CURRENT_GO_VERSION" != "1.21.1" ]; then
    echo "Updating Go to version 1.21.1..."
    sudo rm -rf /usr/local/go
    wget https://dl.google.com/go/go1.21.1.linux-amd64.tar.gz
    sudo tar -xvf go1.21.1.linux-amd64.tar.gz -C /usr/local
fi

# Set Go environment variables
echo "export GOROOT=/usr/local/go" >> $HOME/.zshrc
echo "export GOPATH=$HOME/go" >> $HOME/.zshrc
echo "export PATH=$PATH:/usr/local/go/bin:$GOPATH/bin" >> $HOME/.zshrc
source $HOME/.zshrc

# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y 
source $HOME/.cargo/env

#Give correct permissions to user
sudo chown -R whispernode /home/whispernode/penumbra/target/release/

# Clone Penumbra repository and checkout the specified version
git clone https://github.com/penumbra-zone/penumbra
cd penumbra
git fetch
git checkout v0.69.0

# Build pcli and pd
cargo build --release --bin pcli
cargo build --release --bin pd

#Move binary files 
echo "Moving Binaries"
cd /home/whispernode/penumbra/target/release/
chmod +x pd
chmod +x pcli
sudo mv /home/whispernode/penumbra/target/release/pd /usr/local/bin/pd
sudo mv /home/whispernode/penumbra/target/release/pcli /usr/local/bin/pcli
sudo cp /usr/local/bin/pd /home/whispernode/go/bin/pd
sudo cp /usr/local/bin/pcli /home/whispernode/go/bin/pcli


# Check Versions
echo "Checking pd/pcli versions..."
pd --version
pcli --version

echo "Installing CometBFT..."
# Install CometBFT
cd /home/whispernode
git clone https://github.com/cometbft/cometbft.git
cd cometbft
git checkout v0.37.2

# Update Go modules
go mod tidy

# Compile the cometbft executable
go build -o cometbft ./cmd/cometbft

# Move the compiled executable to the cometbft directory
mv cometbft /home/whispernode/cometbft/

# Proceed with installation
make install

# Increase the number of allowed open file descriptors
ulimit -n 4096

# Request the node name from the user
#echo "Enter the name of your node:"
#read MY_NODE_NAME

# If IP_ADDRESS is empty, prompt the user to enter it manually
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

# Join the testnet with specified external address and moniker
cd /home/whispernode/penumbra
pd testnet unsafe-reset-all
pd testnet join --external-address 142.132.154.53:21956 --moniker $(openssl rand -hex 16)

# Create a new wallet or restore an existing one 
echo "Do you want to create a new wallet or restore an existing one? [new/restore]"
read WALLET_CHOICE
if [ "$WALLET_CHOICE" = "new" ]; then
    SEED_PHRASE=$(pcli init soft-kms generate)
    echo "Your seed phrase is: $SEED_PHRASE"
    echo "Write down your seed phrase and keep it safe. Press any key to continue."
    read -n 1 -s
elif [ "$WALLET_CHOICE" = "restore" ]; then
    pcli init soft-kms import-phrase
    echo "Enter your seed phrase:"
    read SEED_PHRASE
    echo $SEED_PHRASE | pcli init soft-kms import-phrase
else
    echo "Invalid choice. Exiting."
    exit 1
fi

PCLI_DIR="/home/whispernode/go/bin/pcli"

if [ -d "$PCLI_DIR" ] && [ "$(ls -A $PCLI_DIR)" ]; then
    echo "The pcli directory is not empty. Renaming the existing directory..."
    mv "$PCLI_DIR" "${PCLI_DIR}_backup_$(date +%F-%T)"
fi

# Add pcli to the system path for simplified command usage
#echo "export PATH=\$PATH:/home/whispernode/go/bin" >> $HOME/.zshrc
#source $HOME/.zshrc

#Swap Validator Key Files 

echo "Change your config and start services!"
