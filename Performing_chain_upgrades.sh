tmux kill-session -t penumbra
pd export --home ~/.penumbra/testnet_data/node0/pd --export-directory ~/.penumbra/testnet_data/node0/pd-exported-state
mv ~/.penumbra/testnet_data/node0/pd ~/.penumbra/testnet_data/node0/pd-state-backup
git clone https://github.com/penumbra-zone/penumbra
cd penumbra
git fetch
git checkout v0.71.0
cargo build --release --bin pcli
cargo build --release --bin pd
pd migrate --genesis-start "2024-03-28T19:18:38.745760868Z" --target-directory ~/.penumbra/testnet_data/node0/pd-exported-state/ --migrate-archive ~/.penumbra/testnet_data/node0/pd-migrated-state-v0.71.0.tar.gz
mkdir ~/.penumbra/testnet_data/node0/pd && mv ~/.penumbra/testnet_data/node0/pd-exported-state/rocksdb ~/.penumbra/testnet_data/node0/pd/
cp ~/.penumbra/testnet_data/node0/pd-exported-state/genesis.json ~/.penumbra/testnet_data/node0/cometbft/config/genesis.json && cp ~/.penumbra/testnet_data/node0/pd-exported-state/priv_validator_state.json ~/.penumbra/testnet_data/node0/cometbft/data/priv_validator_state.json
find ~/.penumbra/testnet_data/node0/cometbft/data/ -mindepth 1 -maxdepth 1 -type d -exec rm -r {} +
tmux new-session -d -s penumbra '/root/penumbra/target/release/pd start' && tmux split-window -h '/root/cometbft/cometbft start --home ~/.penumbra/testnet_data/node0/cometbft' && tmux attach -t penumbra
