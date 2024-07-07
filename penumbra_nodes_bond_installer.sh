#!/bin/bash

# Ensure the script is running interactively
if [ -z "$PS1" ]; then
    echo "Setting default PS1 as the script is not running interactively."
    export PS1='\h:\w\$ '
fi

# Temporarily change the home directory to avoid sourcing .bashrc
ORIGINAL_HOME=$HOME
export HOME=/tmp

# Define constants
PENUMBRA_VERSION="v0.79.0"
COMETBFT_VERSION="v0.37.5"

# Setup environment
set -euo pipefail
echo "Checking Ubuntu version..."
UBUNTU_VERSION=$(lsb_release -sr)
if (( $(echo "$UBUNTU_VERSION < 22" | bc -l) )); then
    echo "Ubuntu version 22 or higher is required. Your version is $UBUNTU_VERSION."
    exit 1
fi

# Set paths for Go
export GOPATH=${GOPATH:-"$HOME/go"}
export GOROOT=${GOROOT:-"/usr/local/go"}
export PATH="$PATH:$GOROOT/bin:$GOPATH/bin"

# Clean up old installations
echo "Removing old versions of Penumbra and related modules..."
sudo rm -rf /root/penumbra /root/cometbft

# Backup old Penumbra directory if exists
if [ -d "/root/penumbra" ]; then
    mv /root/penumbra /root/penumbra_old
fi

# Set up Tmux for session handling
export TMUX_TMPDIR="/root/.tmux"
mkdir -p "$TMUX_TMPDIR"
tmux start-server

# Clean up existing configuration if present
PCLI_DIR="/root/.local/share/pcli"
if [ -d "$PCLI_DIR" ]; then
    if [ "$(ls -A $PCLI_DIR)" ]; then
        echo "Clearing out existing configuration..."
        rm -rf ${PCLI_DIR:?}/*  # Safe deletion
    fi
fi

# Install necessary packages
sudo apt-get update
sudo apt-get install -y build-essential pkg-config libssl-dev clang git-lfs tmux libclang-dev curl
sudo apt-get install tmux

# Install Go if not present
if ! command -v go > /dev/null; then
    echo "Installing Go..."
    wget https://dl.google.com/go/go1.21.1.linux-amd64.tar.gz
    sudo tar -xvf go1.21.1.linux-amd64.tar.gz -C /usr/local
    export PATH=$PATH:/usr/local/go/bin
fi

# Install Rust
echo "Installing Rust..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# Download and set up Penumbra
git clone https://github.com/penumbra-zone/penumbra
cd penumbra
git fetch
git checkout $PENUMBRA_VERSION
cargo build --release --bin pcli
cargo build --release --bin pd

# Set up CometBFT
cd /root
git clone https://github.com/cometbft/cometbft.git
cd cometbft
git checkout $COMETBFT_VERSION
go mod tidy
go build -o cometbft ./cmd/cometbft

# Move executable if not already in the correct location
if [ ! -f /root/cometbft/cometbft ]; then
    mv cometbft /root/cometbft/
fi

# Prepare for node operation
make install
ulimit -n 4096

# Node setup
echo "Enter the name of your node (moniker):"
read MY_NODE_NAME
echo "If known, enter your server's public IP address (press enter to skip):"
read IP_ADDRESS
NODE_URL="penumbra.nodes.bond"  # Default node URL, change if different

# Start node
echo "Joining network..."
cd /root/penumbra
if [ -n "$IP_ADDRESS" ]; then
    pd network join --moniker "$MY_NODE_NAME" --external-address "$IP_ADDRESS:26656" $NODE_URL
else
    pd network join --moniker "$MY_NODE_NAME" $NODE_URL
fi

# Configuration and clean-up
PCLI_DIR="/tmp/.local/share/pcli"
if [ -d "$PCLI_DIR" ]; then
    rm -rf ${PCLI_DIR:?}/*
fi

# Add binary to PATH
echo "export PATH=\$PATH:/root/penumbra/target/release" >> $HOME/.profile
source $HOME/.profile

# Restore home directory
export HOME=$ORIGINAL_HOME

echo "Installation is complete. Please attach to the tmум window to start the node."
