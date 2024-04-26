#!/bin/bash

# Author: nodes.bond
# Penumbra Version: v0.73.0
# Go Version: 1.21.1
# Cometbft Version: v0.37.5

# Install missing dependencies
sudo apt-get update
sudo apt-get install -y bc  # Install bc for floating point support

# Set error handling
set -euo pipefail

# Check Ubuntu Version
UBUNTU_VERSION=$(lsb_release -sr)
if (( $(echo "$UBUNTU_VERSION < 22" | bc -l) )); then
    echo "This script requires Ubuntu version 22 or higher. Your version is $UBUNTU_VERSION."
    exit 1
fi

# Remove previous versions of Penumbra and related modules
echo "Removing old versions of Penumbra and related modules..."
sudo rm -rf /root/penumbra /root/cometbft

# Rename existing Penumbra directory (for updates)
if [ -d "/root/penumbra" ]; then
    mv /root/penumbra /root/penumbra_old
fi

# Handle non-empty pcli directory
PCLI_DIR="/root/.local/share/pcli"
if [ -d "$PCLI_DIR" ] && [ "$(ls -A $PCLI_DIR)" ]; then
    echo "The pcli directory is not empty."
    echo "Renaming the existing directory..."
    mv "$PCLI_DIR" "${PCLI_DIR}_backup_$(date +%F-%T)"
fi

# Recheck and install other dependencies
sudo apt-get install -y build-essential pkg-config libssl-dev clang git-lfs tmux libclang-dev curl

# Ensure Go is the correct version
CURRENT_GO_VERSION=$(go version | grep -oP 'go\K[0-9.]+')
if [ "$CURRENT_GO_VERSION" != "1.21.1" ]; then
    echo "Updating Go to version 1.21.1..."
    sudo rm -rf /usr/local/go
    wget https://dl.google.com/go/go1.21.1.linux-amd64.tar.gz
    sudo tar -xvf go1.21.1.linux-amd64.tar.gz -C /usr/local
fi

# Set Go environment variables
echo "export GOROOT=/usr/local/go" >> $HOME/.profile
echo "export GOPATH=$HOME/go" >> $HOME/.profile
echo "export PATH=$PATH:/usr/local/go/bin:$GOPATH/bin" >> $HOME/.profile
source $HOME/.profile

# Install Rust and proceed with Penumbra installation
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
git clone https://github.com/penumbra-zone/penumbra
cd penumbra
git fetch
git checkout v0.73.0
cargo build --release --bin pcli
cargo build --release --bin pd
cd /root
git clone https://github.com/cometbft/cometbft.git
cd cometbft
git checkout v0.37.5
go mod tidy
go build -o cometbft ./cmd/cometbft
mv cometbft /root/cometbft/
make install

# Increase file descriptor limit
ulimit -n 4096

# Configure network and wallet
echo "Enter the name of your node:"
read MY_NODE_NAME
IP_ADDRESS=$(curl -4s ifconfig.me)
if [ -z "$IP_ADDRESS" ]; then
    echo "Please enter the server's external IP address manually:"
    read IP_ADDRESS
fi
cd /root/penumbra
./target/release/pd testnet unsafe-reset-all
./target/release/pd testnet join --external-address $IP_ADDRESS:26656 --moniker "$MY_NODE_NAME"

# Set up wallet
echo "Do you want to create a new wallet or restore an existing one? [new/restore]"
read WALLET_CHOICE
if [ "$WALLET_CHOICE" = "new" ]; then
    SEED_PHRASE=$(./target/release/pcli init soft-kms generate)
    echo "Your seed phrase is: $SEED_PHRASE"
    echo "Press any key to continue."
    read -n 1 -s
elif [ "$WALLET_CHOICE" = "restore" ]; then
    echo "Enter your seed phrase:"
    read SEED_PHRASE
    echo $SEED_PHRASE | ./target/release/pcli init soft-kms import-phrase
else
    echo "Exiting due to invalid choice."
    exit 1
fi

echo "Adding pcli to system path for easy access."
echo "export PATH=\$PATH:/root/penumbra/target/release" >> $HOME/.profile
source $HOME/.profile

# Start node and monitoring in tmux
echo "Starting node and CometBFT using tmux."
tmux kill-session -t penumbra
tmux new-session -d -s penumbra '/root/penumbra/target/release/pd start' && tmux split-window -h '/root/cometbft/cometbft start --home ~/.penumbra/testnet_data/node0/cometbft' && tmux attach -t penumbra
