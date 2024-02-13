#!/bin/bash

# Author: nodes.bond
# Penumbra Version: v0.67.0
# Go Version: 1.21.1
# Cometbft Version: v0.37.2

# Check Ubuntu Version
UBUNTU_VERSION=$(lsb_release -sr)
if (( $(echo "$UBUNTU_VERSION < 22" | bc -l) )); then
    echo "This script requires Ubuntu version 22 or higher. Your version is $UBUNTU_VERSION."
    exit 1
fi

# Remove previous versions of Penumbra and related modules
echo "Removing old versions of Penumbra and related modules..."
sudo rm -rf /root/penumbra /root/cometbft /root/.local/share/pcli/

# Rename existing Penumbra directory (for updates)
if [ -d "/root/penumbra" ]; then
    mv /root/penumbra /root/penumbra_old
fi

# Update package list and install dependencies
sudo apt-get update
sudo apt-get install -y build-essential pkg-config libssl-dev clang git-lfs tmux libclang-dev curl

# Install Go 1.21.1
GO_VERSION="1.21.1"
wget https://dl.google.com/go/go${GO_VERSION}.linux-amd64.tar.gz
sudo tar -xvf go${GO_VERSION}.linux-amd64.tar.gz
sudo mv go /usr/local

# Set Go environment variables
echo "export GOROOT=/usr/local/go" >> $HOME/.profile
echo "export GOPATH=$HOME/go" >> $HOME/.profile
echo "export PATH=$GOPATH/bin:$GOROOT/bin:$PATH" >> $HOME/.profile
source $HOME/.profile

# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# Clone Penumbra repository and checkout the specified version
git clone https://github.com/penumbra-zone/penumbra
cd penumbra
git fetch
git checkout v0.67.0

# Build pcli and pd
cargo build --release --bin pcli
cargo build --release --bin pd

# Install CometBFT
cd /root
git clone https://github.com/cometbft/cometbft.git
cd cometbft
git checkout v0.37.2

# Update Go modules
go mod tidy

# Compile the cometbft executable
go build -o cometbft ./cmd/cometbft

# Move the compiled executable to the cometbft directory
mv cometbft /root/cometbft/

# Proceed with installation
make install

# Increase the number of allowed open file descriptors
ulimit -n 4096

# Request the node name from the user
echo "Enter the name of your node:"
read MY_NODE_NAME

# Retrieve the external IP address of the server (ensure IPv4)
IP_ADDRESS=$(curl -4s ifconfig.me)

# Join the testnet with specified external address and moniker
cd /root/penumbra
./target/release/pd testnet unsafe-reset-all
./target/release/pd testnet join --external-address $IP_ADDRESS:26656 --moniker "$MY_NODE_NAME"

# Create a new wallet or restore an existing one 
echo "Do you want to create a new wallet or restore an existing one? [new/restore]"
read WALLET_CHOICE
if [ "$WALLET_CHOICE" = "new" ]; then
    SEED_PHRASE=$(./target/release/pcli init soft-kms generate)
    echo "Your seed phrase is: $SEED_PHRASE"
    echo "Write down your seed phrase and keep it safe. Press any key to continue."
    read -n 1 -s
elif [ "$WALLET_CHOICE" = "restore" ]; then
    ./target/release/pcli init soft-kms import-phrase
    echo "Enter your seed phrase:"
    read SEED_PHRASE
    echo $SEED_PHRASE | ./target/release/pcli init soft-kms import-phrase
else
    echo "Invalid choice. Exiting."
    exit 1
fi

# Add pcli to the system path for simplified command usage
echo "export PATH=\$PATH:/root/penumbra/target/release" >> $HOME/.profile
source $HOME/.profile

# Launch the node and CometBFT in tmux
tmux kill-session -t penumbra
tmux new-session -d -s penumbra '/root/penumbra/target/release/pd start' && tmux split-window -h '/
