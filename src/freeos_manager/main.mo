// main.mo
// Code to run and manage processes handled by the freeos_swap canister working with the icrc1_ledger canister

// CODE START

import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import Error "mo:base/Error";
import Time "mo:base/Time";
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
    #BadFee : { expected_fee : Tokens };
    #BadBurn : { min_burn_amount : Tokens };
    #InsufficientFunds : { balance : Tokens };
    #TooOld;
    #CreatedInFuture : { ledger_time : Timestamp };
    #TemporarilyUnavailable;
    #Duplicate : { duplicate_of : BlockIndex };
    #GenericError : { error_code : Nat; message : Text };
  };

  type TransferResult = {
    #Ok : BlockIndex;
    #Err : TransferError;
  };

  // JESPER - Created custom types to handle contents of HTTP GET request and pass to other functions
  type Time = Time.Time;

  type MessageObject = {
    accountFrom : ?Principal;
    accountTo : ?Principal;
    amount: ?Int;
    time: ?Time;
  };

  // VARIABLES *************************************************************

  let ledger_canister = actor ("mxzaz-hqaaa-aaaar-qaada-cai") : actor {
    icrc1_transfer : (TransferArg) -> async TransferResult;
    icrc1_balance_of : (Account) -> async Nat;
  };

  // Defined the to_principal value here to make it easier to update and be usable by different functions
  // This can be done using { caller } in the future but I haven't been able to get it to work yet
  // Jesper
  let hardCodedToPrincipal = Principal.fromText("tog4r-6yoqs-piw5o-askmx-dwu6g-vncjf-y7gml-qnkb2-yhuao-2cq3c-2ae");
  // testytester
  // let hardCodedPrincipal = Principal.fromText("stp67-22vw7-sgmm7-aqsla-64hid-auh7e-qjsxr-tr3q2-47jtb-qubd7-6qe");

  var to_principal : Principal = hardCodedToPrincipal;

  // Variables needed for the auto-minting process
  var mintTimer : Nat = 0;
  var isMinting : Bool = false;
  var mintStop : Bool = true;

  // Variables needed for the auto-burning process
  var burnTimer : Nat = 0;
  var isBurning : Bool = false;
  var burnStop : Bool = true;

  // JESPER - Created new variables
  // Not used yet
  // let message : MessageObject = {
  //   accountFrom = null;
  //   accountTo = null;
  //   amount = null;
  //   time = null;
  // };

  // JESPER - New variables to be used to set the contents of the transferArgs based on the HTTPS request
  var transferAmount : Tokens = 50000;
  var transferFee : Tokens = 0;

  // Gets the Principal of this canister for use in burning
  // private let minterPrincipal : Principal = Principal.fromText("aaaaa-aa");
  private let minterPrincipal : Principal = Principal.fromText("bkyz2-fmaaa-aaaaa-qaaaq-cai");

  // Creating the accont type variable to use in the burn function
  private let MINTER_ACCOUNT = { owner = minterPrincipal; subaccount = null };
  
  // FUNCTIONS *************************************************************

  // JESPER - Test of burning process
  public shared (msg) func burn() : async (Result<Nat, Text>, Principal) {
    let memoText = "Test burn";
    let memoBlob = Text.encodeUtf8(memoText);
    let ranAtTime = await generateTime();
    let caller : Principal = msg.caller;

    // This doesn't work as the IC doesn't use a null address like other blockchains do
    // let burnAddress : Principal = Principal.fromText("aaaaa-aa"); // This is the IC's null address

    let balance = await ledger_canister.icrc1_balance_of({ owner = to_principal; subaccount = null });

    if(balance < transferAmount + transferFee) {
      return (#err("Insufficient balance to burn " # Nat.toText(transferAmount) # " tokens."), caller);
    };

    let transferArgs = {
      from_subaccount = null;
      to = MINTER_ACCOUNT;
      amount = transferAmount;
      fee = ?transferFee;
      memo = ?memoBlob;
      created_at_time = ?ranAtTime;
    };

    let transferResult = await ledger_canister.icrc1_transfer(transferArgs);
    let callerBalance = await ledger_canister.icrc1_balance_of({ owner = caller; subaccount = null });

    switch (transferResult) {
      case (#Ok(blockIndex)) {
        return (#ok(blockIndex), caller);
      };
      case (#Err(TransferError)) {
        let errorMessage2 = handleError(TransferError, balance, caller, callerBalance);
        throw Error.reject(errorMessage2);
      };
    };
  };

  public shared func setUpMinterBalance() : async (Result<Nat, Text>) {
    let memoText = "Test burn";
    let memoBlob = Text.encodeUtf8(memoText);
    let ranAtTime = await generateTime();
    
    let transferArgs = {
      from_subaccount = null;
      to = MINTER_ACCOUNT;
      amount = transferAmount;
      fee = ?transferFee;
      memo = ?memoBlob;
      created_at_time = ?ranAtTime;
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

  // JESPER - Experimental function to help parse burn errors better
  func handleError(error: TransferError, accountBalance : Nat, caller : Principal, callerBalance : Nat) : Text {
    var errorMessage : Text = "";
    switch error {
      case (#GenericError(err)) {
        errorMessage := err.message;
        errorMessage;
      };
      case (#TemporarilyUnavailable(timeout)) {
        errorMessage := ("Temporarily unavailable: timeout = ");
        errorMessage;
      };
      case (#BadBurn(minBurnAmount)) {
        errorMessage := ("Bad burn: min_burn_amount = ");
        errorMessage;
      };
      case (#Duplicate(duplicateOf)) {
        errorMessage := ("Duplicate: duplicate_of = ");
        errorMessage;
      };
      case (#BadFee(expectedFee)) {
        errorMessage := ("Bad fee: expected_fee = ");
        errorMessage;
      }; 
      case (#CreatedInFuture(ledgerTime)) {
        errorMessage := ("Created in future: ledger_time = ");
        errorMessage;
      };
      case (#TooOld(blockHeight)) {
        errorMessage := ("Too old: block_height = ");
        errorMessage;
      };
      case (#InsufficientFunds(balance)) {
        errorMessage := ("Insufficient funds: balance = " # Principal.toText(to_principal) # " : " # Nat.toText(accountBalance) # " caller is: " # Principal.toText(caller) # "of which balance exists: " # Nat.toText(callerBalance));
        errorMessage;
      };
    };
  };

  // Generates the time that an action has been completed
  // Can be called by any functions that need a timestamp
  func generateTime() : async Timestamp {
    let currentTime : Timestamp = Nat64.fromNat(Int.abs(Time.now()));
    currentTime;
  };

  // Changes the amount that is minted etc.
  // Can be called by the user
  public shared func setTransferAmount(amount : Int) : async Tokens {
    transferAmount := Int.abs(amount);
    transferAmount;
  };

  // Changes the fee exacted on a transaction (default is 0).
  // Can be called by the user
  public shared func setFee(amount : Int) : async Tokens {
    transferFee := Int.abs(amount);
    transferFee;
  };

  public shared (message) func whoami() : async Principal {
    return message.caller;
  };

  // JESPER - Experimental function to be able to change the toPrincipal to mint to the balance where it needs to be
  // Later we could potentially use this to iterate over a range of Principals and change the to address each time
  public shared func setToPrincipal(setPrincipal : Principal) : async Text {
    to_principal := setPrincipal;
    let message : Text = ("To Principal set to " # Principal.toText(to_principal));
    message;
  };

  // Allows manual minting of the amount specified to the user's balance
  // Can be called by the user
  public shared func mint() : async Result<Nat, Text> {
    let memoText = "Test transfer";
    let memoBlob = Text.encodeUtf8(memoText);
    let ranAtTime = await generateTime();

    let transferArgs = {
      from_subaccount = null;
      to = {
        owner = to_principal;
        subaccount = null;
      };
      amount = transferAmount;
      fee = ?transferFee;
      memo = ?memoBlob;
      created_at_time = ?ranAtTime;
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
  public shared func getBalance() : async (Nat, Text, Text) {
    let account = {
      owner = to_principal;
      subaccount = null;
    };

    var mintMessage : Text = "";
    var burnMessage : Text = "";

    let balance = await ledger_canister.icrc1_balance_of(account);
    if (mintStop) {
      mintMessage := "Auto-minting is stopped.";
    } else {
      mintMessage := "Auto-minting is running.";
    };
    if (burnStop) {
      burnMessage := "Auto-burning is stopped.";
    } else {
      burnMessage := "Auto-burning is running.";
    };
    return (balance, mintMessage, burnMessage);
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
      mintTimer := Timer.setTimer(#seconds 10, heartbeatCallback);
    };
    if (burnTimer == 0 and not burnStop) {
      burnTimer := Timer.setTimer(#seconds 30, burnHeartbeatCallback);
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
      mintTimer := Timer.setTimer(#seconds 10, heartbeatCallback);
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

    // Enables auto-minting related functions to start the process
  // Can be called by the user
  public func startBurning() : async () {
    burnStop:= false;
  };
  
  // Resets the timer and runs mint()
  // Called by heartbeat() every 30 seconds
  func burnHeartbeatCallback() : async () {
    if (burnStop) {
      return;  
    };
    if (not isBurning) {
      isBurning := true;
      try {
        ignore burn();
      } catch (e) {
        // Handle any errors that occur during burning
        Debug.print("Burning error: " # Error.message(e));
      };
      isBurning := false;
    };
    // Set the next timer only if burning is still active
    if (burnTimer != 0) {
      burnTimer := Timer.setTimer(#seconds 30, burnHeartbeatCallback);
    };
  };

  // Stops the auto-minting process
  // Can be called by the user
  public func stopBurning() : async () {
    if (burnTimer != 0) {
      Timer.cancelTimer(burnTimer);
      burnTimer := 0;
      burnStop := true;
    };
  };

  // JESPER - Test of a handbrake function to stop all auto processes dead in their tracks
  // Can be called by the user
  public shared func handbrake() : async () {
    burnStop := true;
    mintStop := true;
    isMinting := false;
    isBurning := false;
  };

};

// CODE END