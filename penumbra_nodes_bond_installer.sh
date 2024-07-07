#!/bin/bash

# Check if running interactively
if [ -z "$PS1" ]; then
    echo "Setting default PS1 as the script is not running interactively."
    export PS1='\h:\w\$ '
fi

# Temporarily change the home directory to avoid sourcing .bashrc
ORIGINAL_HOME=$HOME
export HOME=/tmp

# Author: nodes.bond
# Penumbra Version: v0.79.0
# Go Version: 1.21.1
# Cometbft Version: v0.37.5

set -euo pipefail

# Check Ubuntu Version
UBUNTU_VERSION=$(lsb_release -sr)
if (( $(echo "$UBUNTU_VERSION < 22" | bc -l) )); then
    echo "This script requires Ubuntu version 22 or higher. Your version is $UBUNTU_VERSION."
    exit 1
fi

# Set default GOPATH, GOROOT and update PATH
export GOPATH=${GOPATH:-"$HOME/go"}
export GOROOT=${GOROOT:-"/usr/local/go"}
export PATH="$PATH:$GOROOT/bin:$GOPATH/bin"

# Remove previous versions of Penumbra and related modules
echo "Removing old versions of Penumbra and related modules..."
sudo rm -rf /root/penumbra /root/cometbft

# Rename existing Penumbra directory
if [ -d "/root/penumbra" ]; then
    mv /root/penumbra /root/penumbra_old
fi

# Explicitly set the tmux temporary directory
export TMUX_TMPDIR="/root/.tmux"
mkdir -p "$TMUX_TMPDIR"

# Ensure the tmux server is running correctly
tmux start-server

# Handle non-empty pcli directory
PCLI_DIR="/root/.local/share/pcli"
if [ -d "$PCLI_DIR" ]; then
    if [ "$(ls -A $PCLI_DIR)" ]; then
        echo "The pcli directory at $PCLI_DIR is not empty."
        echo "Existing contents will be removed to continue with a clean initialization."
        rm -rf ${PCLI_DIR:?}/*  # Using parameter expansion to avoid catastrophic deletion
    fi
fi

# Update package list and install dependencies
sudo apt-get update
sudo apt-get install -y build-essential pkg-config libssl-dev clang git-lfs tmux libclang-dev curl
sudo apt-get install tmux

# Check and install Go if not present
if ! command -v go > /dev/null; then
    echo "Go is not installed. Installing Go..."
    wget https://dl.google.com/go/go1.21.1.linux-amd64.tar.gz
    sudo tar -xvf go1.21.1.linux-amd64.tar.gz -C /usr/local
    export PATH=$PATH:/usr/local/go/bin
fi

# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# Clone and set up Penumbra
git clone https://github.com/penumbra-zone/penumbra
cd penumbra
git fetch
git checkout v0.79.0
cargo build --release --bin pcli
cargo build --release --bin pd

# Install and set up CometBFT
cd /root
git clone https://github.com/cometbft/cometbft.git
cd cometbft
git checkout v0.37.5
go mod tidy

# Compile the cometbft executable
go build -o cometbft ./cmd/cometbft
sudo cp cometbft /usr/local/bin/cometbft

# Prepare for node operation
make install
ulimit -n 4096

# Set up node configuration
echo "Enter the name of your node:"
read MY_NODE_NAME
echo "Enter the external IP address of your node (leave blank if behind a firewall):"
read IP_ADDRESS

# Join the network
cd /root/penumbra
./target/release/pd testnet join --moniker "$MY_NODE_NAME" --external-address "$IP_ADDRESS:26656" http://penumbra.nodes.bond:26657

# Fetch genesis file
curl -L https://your.genesis.json.url -o /root/.penumbra/network_data/node0/cometbft/config/genesis.json

# Configure systemd services for Penumbra and CometBFT
curl --proto '=https' --tlsv1.2 -LsSf https://raw.githubusercontent.com/penumbra-zone/penumbra/main/deployments/systemd/penumbra.service > penumbra.service
sed -i -E "s/User=penumbra/User=$(whoami)/g" penumbra.service
sudo cp penumbra.service /etc/systemd/system/penumbra.service

curl --proto '=https' --tlsv1.2 -LsSf https://raw.githubusercontent.com/penumbra-zone/penumbra/main/deployments/systemd/cometbft.service > cometbft.service
sed -i -E "s/User=penumbra/User=$(whoami)/g" cometbft.service
sed -i -E "s+ExecStart=/usr/local/bin/cometbft start --home /home/penumbra/.penumbra/network_data/node0/cometbft+ExecStart=/usr/local/bin/cometbft start --home $HOME/.penumbra/network_data/node0/cometbft+g" cometbft.service
sudo cp cometbft.service /etc/systemd/system/cometbft.service

sudo systemctl daemon-reload
sudo systemctl start penumbra
sudo systemctl start cometbft
sudo systemctl enable penumbra
sudo systemctl enable cometbft

echo "Installation is complete. Penumbra and CometBFT services are now running."
