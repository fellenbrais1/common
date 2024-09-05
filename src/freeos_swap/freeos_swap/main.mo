import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Error "mo:base/Error";
import Time "mo:base/Time";
import Timer "mo:base/Timer";
import Debug "mo:base/Debug";

actor {
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

  let ledger_canister = actor ("mxzaz-hqaaa-aaaar-qaada-cai") : actor {
    icrc1_transfer : (TransferArg) -> async TransferResult;
    icrc1_balance_of : (Account) -> async Nat;
  };

  // Timer variable to store the timer ID
  // var mintTimer : Timer.TimerId = 0;

  // Defined the to_principal value here to make it easier to update and be usable by different functions
  let to_principal = Principal.fromText("tog4r-6yoqs-piw5o-askmx-dwu6g-vncjf-y7gml-qnkb2-yhuao-2cq3c-2ae");

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

  var mintTimer : Nat = 0;
  var isMinting : Bool = false;
  var mintStop : Bool = true;

  // Heartbeat function to run mint every 30 seconds
  public func startMinting() : async () {
    mintStop:= false;
  };
  
  system func heartbeat() : async () {
    if (mintTimer == 0 and not mintStop) {
      mintTimer := Timer.setTimer(#seconds 30, heartbeatCallback);
    };
  };

  // Callback function for the timer
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

  // Function to stop the minting process
  public func stopMinting() : async () {
    if (mintTimer != 0) {
      Timer.cancelTimer(mintTimer);
      mintTimer := 0;
      mintStop := true;
    };
  };

};