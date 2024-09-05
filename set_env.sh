#!/bin/bash

export PRE_MINTED_TOKENS=10_000_000_000
dfx identity use default
export DEFAULT=$(dfx identity get-principal)
export TRANSFER_FEE=0
dfx identity use archive_controller
export ARCHIVE_CONTROLLER=$(dfx identity get-principal)
export TRIGGER_THRESHOLD=2000
export CYCLE_FOR_ARCHIVE_CREATION=10000000000000
export NUM_OF_BLOCK_TO_ARCHIVE=1000
export TOKEN_NAME="Lift Cash"
export TOKEN_SYMBOL="LIFT"
# dfx identity use minter
# export MINTER=$(dfx identity get-principal)
export MINTER=bkyz2-fmaaa-aaaaa-qaaaq-cai
export FEATURE_FLAGS=false
dfx identity use Jesper


