// main.mo
// Code to run and manage processes handled by the freeos_swap canister working with the icrc1_ledger canister

// TODO
// Remove any functions that only need to run from the minter
// Add the actor for the freeos_swap canister and the function call for the mint function so it can be called here
// Change the mint function on this canister that calls mint on the freeos_swap canister
// Remove JESPER comments when changes have been discussed/ passed on

// NOTES
// At the moment the mint function can only be called from the freeos_swap canister
// The burn function can only be called from freeos_manager by specifying the Principal of the account to burn from
// Recent changes are denoted by JESPER comments

// CODE START

// JESPER - Added a few new modules as necessary (Int, Time, Debug)
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

  // JESPER - Changed this object to the variant object that is expected by icrc1_transfer
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

  // JESPER - Created custom type for the generation of Timestamp values in mint() and burn()
  type Time = Time.Time;

  // JESPER - Set up this new type but not sure if it will be useful
  type MessageObject = {
    accountFrom : ?Principal;
    accountTo : ?Principal;
    amount: ?Int;
    time: ?Time;
  };

  // VARIABLES *************************************************************

  // JESPER - Added the icrc1_balance_of function from the icrc1_ledger to this actor
  let ledger_canister = actor ("mxzaz-hqaaa-aaaar-qaada-cai") : actor {
    icrc1_transfer : (TransferArg) -> async TransferResult;
    icrc1_balance_of : (Account) -> async Nat;
  };

  // JESPER - Defined the to_principal value here to make it easier to update and be used
  // This could be done using '{ caller } / msg.caller' in the future but I haven't been able to get it to work yet
  // Identity: Jesper
  let hardCodedToPrincipal = Principal.fromText("tog4r-6yoqs-piw5o-askmx-dwu6g-vncjf-y7gml-qnkb2-yhuao-2cq3c-2ae");
  // Identity: testytester
  // let hardCodedPrincipal = Principal.fromText("stp67-22vw7-sgmm7-aqsla-64hid-auh7e-qjsxr-tr3q2-47jtb-qubd7-6qe");

  // JESPER - Defines the default value of to_principal to the value of hardCodedToPrincipal
  var to_principal : Principal = hardCodedToPrincipal;

  // JESPER - Added 2 variables needed for the auto-minting process (isMinting, mintStop)
  var mintTimer : Nat = 0;
  var isMinting : Bool = false;
  var mintStop : Bool = true;

  // JESPER - Variables needed for the auto-burning process (all new)
  var burnTimer : Nat = 0;
  var isBurning : Bool = false;
  var burnStop : Bool = true;

  // JESPER - Creating new messageObject type variable
  // Not used yet
  // let message : MessageObject = {
  //   accountFrom = null;
  //   accountTo = null;
  //   amount = null;
  //   time = null;
  // };

  // JESPER - New variables to be used to set the contents of the transferArgs for mint and burn functions etc.
  var transferAmount : Tokens = 50000;
  var transferFee : Tokens = 0;

  // JESPER - Gets the Principal of this canister for use in burning
  // private let minterPrincipal : Principal = Principal.fromText("aaaaa-aa"); // Principal of the current canister
  private let minterPrincipal : Principal = Principal.fromText("bkyz2-fmaaa-aaaaa-qaaaq-cai");

  // JESPER - Creating the account type variable to use in the burn() function
  private let MINTER_ACCOUNT = { owner = minterPrincipal; subaccount = null };
  
  // FUNCTIONS *************************************************************

  // JESPER - Added function to burn tokens (can only be called from outside the minter, see notes)
  // Can be called from the freeos_manager canister
  public shared (msg) func burn() : async (Result<Nat, Text>, Principal) {
    let memoText = "Test burn";
    let memoBlob = Text.encodeUtf8(memoText);
    let ranAtTime = await generateTime();
    let caller : Principal = msg.caller;

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

  // JESPER - Added function to help parse burn errors better and print debug information, can be mothballed after testing is completed
  // Called by burn()
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

  // JESPER - Added function that generates the time that an action has been completed
  // Called by mint(), burn()
  func generateTime() : async Timestamp {
    let currentTime : Timestamp = Nat64.fromNat(Int.abs(Time.now()));
    currentTime;
  };

  // JESPER - Added function to change the amount that is transferred in minting/ butning etc.
  // Can be called by the user
  public shared func setTransferAmount(amount : Int) : async Tokens {
    transferAmount := Int.abs(amount);
    transferAmount;
  };

  // JESPER - Changes the fee exacted on a transaction (default is 0).
  // Can be called by the user
  public shared func setFee(amount : Int) : async Tokens {
    transferFee := Int.abs(amount);
    transferFee;
  };

  // JESPER - Added a function to print the Principal of the caller, this can be mothballed now 
  // Can be called by the user
  public shared (message) func whoami() : async Principal {
    return message.caller;
  };

  // JESPER - Added function to be able to change the toPrincipal to mint and burn as needed
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

  // JESPER - Added a function to display the balance of the toPrincipal Principal
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

  // JESPER - Added function to enable auto-minting to start
  // Can be called by the user
  public func startMinting() : async () {
    mintStop:= false;
  };
  
  // JESPER - Changed this function to create timers for the auto-minting and auto-burning processes to run every few seconds as defined
  // Automatically runs and has an effect if the conditions in if blocks are met
  system func heartbeat() : async () {
    if (mintTimer == 0 and not mintStop) {
      mintTimer := Timer.setTimer(#seconds 10, heartbeatCallback);
    };
    if (burnTimer == 0 and not burnStop) {
      burnTimer := Timer.setTimer(#seconds 30, burnHeartbeatCallback);
    };
  };

  // Resets the mintTimer and runs mint()
  // Called by heartbeat() every 10 seconds
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

  // JESPER - Added a function to stop the auto-minting process
  // Can be called by the user
  public func stopMinting() : async () {
    if (mintTimer != 0) {
      Timer.cancelTimer(mintTimer);
      mintTimer := 0;
      mintStop := true;
    };
  };

  // JESPER - Added function to enable auto-burning to start
  // Can be called by the user
  public func startBurning() : async () {
    burnStop:= false;
  };
  
  // JESPER - Added function to reset the burnTimer and run burn()
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

  // JESPER - Added function to stop the auto-burning process
  // Can be called by the user
  public func stopBurning() : async () {
    if (burnTimer != 0) {
      Timer.cancelTimer(burnTimer);
      burnTimer := 0;
      burnStop := true;
    };
  };

  // JESPER - Added a handbrake function to stop all auto processes dead in their tracks
  // Can be called by the user
  public shared func handbrake() : async () {
    burnStop := true;
    mintStop := true;
    isMinting := false;
    isBurning := false;
  };

};

// CODE END