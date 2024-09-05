# Using icrc1_ledger and freeos_swap canisters

This set of canisters creates LIFT (Lift Cash) token.
Then it demonstrates how to mint by calling the freeos_swap canister's mint function.
There is also an auto-minting capability that be turned off or on by calling 'startMinting()' and 'stopMinting()' on the 'freeos_swap' canister.

N.B. At the moment you will have to create your own ids, e.g. for the recipient user specified in freeos_swap main.mo
Later this will hopefully be automated, at least to some extent.



## Step 1: Download the latest icrc1_ledger wasm and did file
(! This step hasn't been needed yet, but could be needed to keep a proper deployment up to date)

Run the (Linux/Mac) command:
`source ./download_latest_icrc1_ledger.sh`

The files ('icrc1_ledger.did' and 'icrc1_ledger.wasm.gz') should be placed in the 'src/lift' directory.



## Step 2: Build all of the canisters
(! This step hasn't been needed yet, but could be dependent on the OS and other factors, for me it is unnecessary)

Run the command:
`dfx build`



## Step 3: Deploy the freeos_swap canister

Run the command:
`dfx deploy freeos_swap`

Take note of the canister id generated for 'freeos_swap'. 
This is the 'minter principal' required by the 'icrc1_ledger' canister. 
The 'freeos_swap' canister will become the only entity capable of minting tokens on the 'icrc1_ledger' canister.



## Step 4: Set up the environment variables used in step 5:

Edit the 'set_env.sh' file to set 'MINTER' equal to the 'freeos_swap' canister id.

The line we need to change should look like this:
`export MINTER=bkyz2-fmaaa-aaaaa-qaaaq-cai` 
(With the principal id of your instance of the 'freeos_swap' canister)

Then run this shell file using this (Linux/Mac) command:
`source ./set_env.sh`

This will set up the variables needed for the next step.



## Step 5: Command to deploy the icrc1_ledger canister:

Make sure you are using the same identity you deployed the 'freeos_swap' canister from or you will encounter an error here.

Run this shell file using this (Linux/Mac) command:
`source ./deploy_icrc1.sh`

Alternatively, we can run the same command as in the shell file in the CLI (not including the opening and closing triple backticks):

```
dfx deploy icrc1_ledger --specified-id mxzaz-hqaaa-aaaar-qaada-cai --argument "(variant {Init =
record {
token_symbol = \"${TOKEN_SYMBOL}\";
     token_name = \"${TOKEN_NAME}\";
minting_account = record { owner = principal \"${MINTER}\" };
     transfer_fee = ${TRANSFER_FEE};
     metadata = vec {};
     feature_flags = opt record{icrc2 = ${FEATURE_FLAGS}};
     initial_balances = vec { record { record { owner = principal \"${DEFAULT}\"; }; ${PRE_MINTED_TOKENS}; }; };
     archive_options = record {
         num_blocks_to_archive = ${NUM_OF_BLOCK_TO_ARCHIVE};
         trigger_threshold = ${TRIGGER_THRESHOLD};
         controller_id = principal \"${ARCHIVE_CONTROLLER}\";
cycles_for_archive_creation = opt ${CYCLE_FOR_ARCHIVE_CREATION};
};
}
})"
```

This will deploy the 'icrc1_ledger' canister with all of the arguments needed for proper connectedness and operation.



## Step 6: Call freeos_swap mint function to transfer 50,000 tokens from the minter account to user blwz3-4wsku-3otjv-yriaj-2hhdr-3gh3e-x4z7v-psn6e-ent7z-eytoo-mqe

Run the following canister call in the CLI:
`dfx canister call freeos_swap mint '()'`

We should get the response if it is working as intended: 
`(variant { Ok = 1 : nat })`

We can call any of the public functions on the 'freeos_swap' and 'icrc1_ledger' canisters, but to test more easily, use the Candid UI links generated.
