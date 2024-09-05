// main.mo
// Code to run and manage processes handled by the freeos_swap canister working with the icrc1_ledger canister

// CODE START

import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Error "mo:base/Error";
import Timer "mo:base/Timer";
import Debug "mo:base/Debug";

actor {

  // TYPES *************************************************************

  type Subaccount = Blob;
  type Tokens = Nat;
  type Timestamp = Nat64;

  type Account = {
    owner : Principal;
    subaccount : ?Subaccount;
  };

  type Result<Ok, Err> = {
    #ok : Ok;
    #err : Err;
  };

  type TransferArg = {
    from_subaccount : ?Subaccount;
    to : Account;
    amount : Tokens;
    fee : ?Tokens;
    memo : ?Blob;
    created_at_time : ?Timestamp;
  };

  type BlockIndex = Nat;

  type TransferError = {
    BadFee : { expected_fee : Tokens };
    BadBurn : { min_burn_amount : Tokens };
    InsufficientFunds : { balance : Tokens };
    TooOld : Nat;
    CreatedInFuture : { ledger_time : Timestamp };
    TemporarilyUnavailable : Nat;
    Duplicate : { duplicate_of : BlockIndex };
    GenericError : { error_code : Nat; message : Text };
  };

  type TransferResult = {
    #Ok : BlockIndex;
    #Err : TransferError;
  };

  // VARIABLES *************************************************************

  let ledger_canister = actor ("mxzaz-hqaaa-aaaar-qaada-cai") : actor {
    icrc1_transfer : (TransferArg) -> async TransferResult;
    icrc1_balance_of : (Account) -> async Nat;
  };

  // Defined the to_principal value here to make it easier to update and be usable by different functions
  let to_principal = Principal.fromText("tog4r-6yoqs-piw5o-askmx-dwu6g-vncjf-y7gml-qnkb2-yhuao-2cq3c-2ae");

  // Variables needed for the auto-minting process
  var mintTimer : Nat = 0;
  var isMinting : Bool = false;
  var mintStop : Bool = true;

  // FUNCTIONS *************************************************************
  
  // Allows manual minting of the amount specified to the user's balance
  // Can be called by the user
  public shared func mint() : async Result<Nat, Text> {
    let memoText = "Test transfer";
    let memoBlob = Text.encodeUtf8(memoText);

    let transferArgs = {
      from_subaccount = null;
      to = {
        owner = to_principal;
        subaccount = null;
      };
      amount = 50000;
      fee = ?0;
      memo = ?memoBlob;
      created_at_time = null;
    };

    let transferResult = await ledger_canister.icrc1_transfer(transferArgs);

    switch (transferResult) {
      case (#Ok(blockIndex)) {
        return #ok(blockIndex);
      };
      case (#Err(_transferError)) {
        throw Error.reject("Transfer error");
      };
    };
  };

  // Allows the function to display balance of the user in the icrc1_ledger canister to be run in freeos_swap
  // Outputs the balance of the user and a message of whether the auto-minting process is running
  // Can be called by the user
  public shared func getBalance() : async (Nat, Text) {
    let account = {
      owner = to_principal;
      subaccount = null;
    };

    var message : Text = "";

    let balance = await ledger_canister.icrc1_balance_of(account);
    if (mintStop) {
      message := "Minting is stopped.";
    } else {
      message := "Minting is running.";
    };
    return (balance, message);
  };

  // Enables auto-minting related functions to start the process
  // Can be called by the user
  public func startMinting() : async () {
    mintStop:= false;
  };
  
  // Creates a timer for the auto-minting process to run every 30 seconds
  // Automatically runs and has an effect if mintStop == false
  system func heartbeat() : async () {
    if (mintTimer == 0 and not mintStop) {
      mintTimer := Timer.setTimer(#seconds 30, heartbeatCallback);
    };
  };

  // Resets the timer and runs mint()
  // Called by heartbeat() every 30 seconds
  func heartbeatCallback() : async () {
    if (mintStop) {
      return;  
    };
    if (not isMinting) {
      isMinting := true;
      try {
        ignore mint();
      } catch (e) {
        // Handle any errors that occur during minting
        Debug.print("Minting error: " # Error.message(e));
      };
      isMinting := false;
    };
    // Set the next timer only if minting is still active
    if (mintTimer != 0) {
      mintTimer := Timer.setTimer(#seconds 30, heartbeatCallback);
    };
  };

  // Stops the auto-minting process
  // Can be called by the user
  public func stopMinting() : async () {
    if (mintTimer != 0) {
      Timer.cancelTimer(mintTimer);
      mintTimer := 0;
      mintStop := true;
    };
  };

};

// CODE END