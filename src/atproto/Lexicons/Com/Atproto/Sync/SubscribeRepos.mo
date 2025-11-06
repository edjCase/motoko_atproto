import CID "mo:cid@1";
import DID "mo:did@3";
import TID "mo:tid@1";

module {
  // com.atproto.sync.subscribeRepos
  // Repository event stream, aka Firehose endpoint. Outputs repo commits with diff data, and identity update events, for all repositories on the current server. See the atproto specifications for details around stream sequencing, repo versioning, CAR diff format, and more. Public and does not require auth; implemented by PDS and Relay.

  public type Params = {
    cursor : ?Int;
  };

  public type Error = {
    #futureCursor;
    #consumerTooSlow : { message : ?Text };
  };

  public type Message = {
    #commit : Commit;
    #sync : Sync;
    #identity : Identity;
    #account : Account;
    #info : Info;
  };

  public type Commit = {
    seq : Int;
    rebase : Bool;
    tooBig : Bool;
    repo : DID.Plc.DID;
    commit : CID.CID;
    rev : TID.TID;
    since : ?TID.TID;
    blocks : Blob;
    ops : [RepoOp];
    blobs : [CID.CID];
    prevData : ?CID.CID;
    time : Text;
  };

  public type Sync = {
    seq : Int;
    did : DID.DID;
    blocks : Blob;
    rev : Text;
    time : Text;
  };

  public type Identity = {
    seq : Int;
    did : DID.DID;
    time : Text;
    handle : ?Text;
  };

  public type Account = {
    seq : Int;
    did : DID.DID;
    time : Text;
    active : Bool;
    status : ?AccountStatus;
  };

  public type AccountStatus = {
    #takendown;
    #suspended;
    #deleted;
    #deactivated;
    #desynchronized;
    #throttled;
  };

  public type Info = {
    name : InfoName;
    message : ?Text;
  };

  public type InfoName = {
    #outdatedCursor;
  };

  public type RepoOp = {
    action : RepoOpAction;
    path : Text;
    cid : ?CID.CID;
    prev : ?CID.CID;
  };

  public type RepoOpAction = {
    #create;
    #update;
    #delete;
  };

};
