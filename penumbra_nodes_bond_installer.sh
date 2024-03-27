#!/bin/bash

# Author: nodes.bond
# Penumbra Version: v0.70.1
# Go Version: 1.21.1
# Cometbft Version: v0.37.5

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
    echo "Renaming the existing directory to ${PCLI_DIR}_backup_$(date +%F-%T)..."
    mv "$PCLI_DIR" "${PCLI_DIR}_backup_$(date +%F-%T)"
fi

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
echo "export GOROOT=/usr/local/go" >> $HOME/.profile
echo "export GOPATH=$HOME/go" >> $HOME/.profile
echo "export PATH=$PATH:/usr/local/go/bin:$GOPATH/bin" >> $HOME/.profile
source $HOME/.profile

# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# Clone Penumbra repository and checkout the specified version
git clone https://github.com/penumbra-zone/penumbra
cd penumbra
git fetch
git checkout v0.70.1

# Build pcli and pd
cargo build --release --bin pcli
cargo build --release --bin pd

# Install CometBFT
cd /root
git clone https://github.com/cometbft/cometbft.git
cd cometbft
git checkout v0.37.5

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

# If IP_ADDRESS is empty, prompt the user to enter it manually
IP_ADDRESS=$(curl -4s ifconfig.me)
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
cd /root/penumbra
./target/release/pd testnet unsafe-reset-all
./target/release/pd testnet join --external-address $IP_ADDRESS:26656 --moniker "$MY_NODE_NAME"

# Handle non-empty pcli directory
PCLI_DIR="/root/.local/share/pcli"
if [ -d "$PCLI_DIR" ] && [ "$(ls -A $PCLI_DIR)" ]; then
    echo "The pcli directory is not empty."
    echo "Choose an action:"
    echo "1) Rename and backup the existing directory"
    echo "2) Delete the existing directory (Warning: This will remove all existing data)"
    read -p "Enter choice [1-2]: " choice

    case $choice in
        1)
            BACKUP_DIR="${PCLI_DIR}_backup_$(date +%F-%T)"
            echo "Renaming the existing directory to $BACKUP_DIR..."
            mv "$PCLI_DIR" "$BACKUP_DIR"
            ;;
        2)
            echo "Removing the existing pcli directory..."
            rm -rf "$PCLI_DIR"
            ;;
        *)
            echo "Invalid choice. Exiting."
            exit 1
            ;;
    esac
fi

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
tmux new-session -d -s penumbra '/root/penumbra/target/release/pd start' && tmux split-window -h '/root/cometbft/cometbft start --home ~/.penumbra/testnet_data/node0/cometbft' && tmux attach -t penumbra
