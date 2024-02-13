# Penumbra Node Installer

## Description
This script is designed for the automated installation and configuration of a Penumbra node. It includes all necessary steps, from setting up the environment to launching the node, ensuring a seamless setup process.

## Prerequisites
- Ubuntu version 22 or higher
- Internet connection
- Sufficient disk space and memory

## Installation Steps
1. The script removes previous versions of Penumbra and related modules.
2. Renames existing Penumbra directory for updates.
3. Updates package list and installs dependencies.
4. Installs Go 1.21.1 and sets environment variables.
5. Installs Rust and sets up the environment.
6. Clones the Penumbra repository and checks out the specified version.
7. Builds `pcli` and `pd`.
8. Installs CometBFT.
9. Updates Go modules and compiles the cometbft executable.
10. Increases the number of allowed open file descriptors.
11. Requests node name from the user.
12. Retrieves the external IP address of the server.
13. Joins the testnet with the specified external address and moniker.
14. Offers to create a new wallet or restore an existing one.
15. Adds `pcli` to the system path for simplified command usage.
16. Launches the node and CometBFT in tmux.

## Usage
To run the script, simply execute:
```bash
chmod +x penumbra_nodes_bond_installer.sh
./penumbra_nodes_bond_installer.sh
