import CID "mo:cid@1";
import DID "mo:did@3";
import TID "mo:tid@1";
import Json "mo:json@1";
import Array "mo:core@1/Array";
import DagCbor "mo:dag-cbor@2";
import Blob "mo:core@1/Blob";
import DynamicArray "mo:xtended-collections@0/DynamicArray";

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
  public type DagCborMessage = {
    header : DagCbor.Value;
    payload : DagCbor.Value;
  };

  public func errorToDagCbor(error : Error) : DagCborMessage {
    let header = #map([
      ("op", #int(-1)),
    ]);
    let (kind, message) = switch (error) {
      case (#futureCursor) ("FutureCursor", null);
      case (#consumerTooSlow(details)) ("ConsumerTooSlow", details.message);
    };
    let payload = switch (message) {
      case (?m) #map([
        ("error", #text(kind)),
        ("message", #text(m)),
      ]);
      case (null) #map([
        ("error", #text(kind)),
      ]);
    };
    { header; payload };
  };

  public func messageToDagCbor(message : Message) : DagCborMessage {
    switch (message) {
      case (#commit(commit)) {
        let header = #map([
          ("op", #int(1)),
          ("t", #text("#commit")),
        ]);

        let opsArray = commit.ops |> Array.map(
          _,
          func(op : RepoOp) : DagCbor.Value {
            let action = switch (op.action) {
              case (#create) { #text("create") };
              case (#update) { #text("update") };
              case (#delete) { #text("delete") };
            };

            let fields = DynamicArray.DynamicArray<(Text, DagCbor.Value)>(4);
            fields.add(("action", action));
            fields.add(("path", #text(op.path)));
            // cid is required (but nullable)
            fields.add((
              "cid",
              switch (op.cid) {
                case (?c) { #cid(c) };
                case (null) { #null_ };
              },
            ));
            // prev is optional - only include when present
            switch (op.prev) {
              case (?p) { fields.add(("prev", #cid(p))) };
              case (null) {};
            };

            #map(DynamicArray.toArray(fields));
          },
        );

        let blobsArray = commit.blobs |> Array.map(
          _,
          func(cid : CID.CID) : DagCbor.Value {
            #cid(cid);
          },
        );

        let fields = DynamicArray.DynamicArray<(Text, DagCbor.Value)>(13);
        fields.add(("blobs", #array(blobsArray)));
        fields.add(("blocks", #bytes(Blob.toArray(commit.blocks))));
        fields.add(("commit", #cid(commit.commit)));
        fields.add(("ops", #array(opsArray)));
        // prevData is optional
        switch (commit.prevData) {
          case (?p) { fields.add(("prevData", #cid(p))) };
          case (null) {};
        };
        fields.add(("rebase", #bool(commit.rebase)));
        fields.add(("repo", #text(DID.Plc.toText(commit.repo))));
        fields.add(("rev", #text(TID.toText(commit.rev))));
        fields.add(("seq", #int(commit.seq)));
        // since is required (but nullable)
        fields.add((
          "since",
          switch (commit.since) {
            case (?s) { #text(TID.toText(s)) };
            case (null) { #null_ };
          },
        ));
        fields.add(("time", #text(commit.time)));
        fields.add(("tooBig", #bool(commit.tooBig)));

        let payload = #map(DynamicArray.toArray(fields));

        { header; payload };
      };

      case (#sync(sync)) {
        let header = #map([
          ("op", #int(1)),
          ("t", #text("#sync")),
        ]);

        let payload = #map([
          ("blocks", #bytes(Blob.toArray(sync.blocks))),
          ("did", #text(DID.toText(sync.did))),
          ("rev", #text(sync.rev)),
          ("seq", #int(sync.seq)),
          ("time", #text(sync.time)),
        ]);

        { header; payload };
      };

      case (#identity(identity)) {
        let header = #map([
          ("op", #int(1)),
          ("t", #text("#identity")),
        ]);

        let payload = #map([
          ("did", #text(DID.toText(identity.did))),
          (
            "handle",
            switch (identity.handle) {
              case (?h) { #text(h) };
              case (null) { #null_ };
            },
          ),
          ("seq", #int(identity.seq)),
          ("time", #text(identity.time)),
        ]);

        { header; payload };
      };

      case (#account(account)) {
        let header = #map([
          ("op", #int(1)),
          ("t", #text("#account")),
        ]);

        let statusValue = switch (account.status) {
          case (?#takendown) { #text("takendown") };
          case (?#suspended) { #text("suspended") };
          case (?#deleted) { #text("deleted") };
          case (?#deactivated) { #text("deactivated") };
          case (?#desynchronized) { #text("desynchronized") };
          case (?#throttled) { #text("throttled") };
          case (null) { #null_ };
        };

        let payload = #map([
          ("active", #bool(account.active)),
          ("did", #text(DID.toText(account.did))),
          ("seq", #int(account.seq)),
          ("status", statusValue),
          ("time", #text(account.time)),
        ]);

        { header; payload };
      };

      case (#info(info)) {
        let header = #map([
          ("op", #int(1)),
          ("t", #text("#info")),
        ]);

        let nameValue = switch (info.name) {
          case (#outdatedCursor) { #text("OutdatedCursor") };
        };

        let payload = #map([
          (
            "message",
            switch (info.message) {
              case (?m) { #text(m) };
              case (null) { #null_ };
            },
          ),
          ("name", nameValue),
        ]);

        { header; payload };
      };
    };
  };

  public func toJson(message : Message) : Json.Json {
    switch (message) {
      case (#commit(commit)) {
        let opsJson = commit.ops |> Array.map(
          _,
          func(op : RepoOp) : Json.Json {
            let action = switch (op.action) {
              case (#create) { #string("create") };
              case (#update) { #string("update") };
              case (#delete) { #string("delete") };
            };
            #object_([
              ("action", action),
              ("path", #string(op.path)),
              (
                "cid",
                switch (op.cid) {
                  case (?c) { #string(CID.toText(c)) };
                  case (null) { #null_ };
                },
              ),
              (
                "prev",
                switch (op.prev) {
                  case (?p) { #string(CID.toText(p)) };
                  case (null) { #null_ };
                },
              ),
            ]);
          },
        );

        let blobsJson = commit.blobs |> Array.map(
          _,
          func(cid : CID.CID) : Json.Json {
            #string(CID.toText(cid));
          },
        );

        #object_([
          ("$type", #string("com.atproto.sync.subscribeRepos#commit")),
          ("seq", #number(#int(commit.seq))),
          ("rebase", #bool(commit.rebase)),
          ("tooBig", #bool(commit.tooBig)),
          ("repo", #string(DID.Plc.toText(commit.repo))),
          ("commit", #string(CID.toText(commit.commit))),
          ("rev", #string(TID.toText(commit.rev))),
          (
            "since",
            switch (commit.since) {
              case (?s) { #string(TID.toText(s)) };
              case (null) { #null_ };
            },
          ),
          ("blocks", #string("<blob>")), // Blob representation
          ("ops", #array(opsJson)),
          ("blobs", #array(blobsJson)),
          (
            "prevData",
            switch (commit.prevData) {
              case (?p) { #string(CID.toText(p)) };
              case (null) { #null_ };
            },
          ),
          ("time", #string(commit.time)),
        ]);
      };
      case (#sync(sync)) {
        #object_([
          ("$type", #string("com.atproto.sync.subscribeRepos#sync")),
          ("seq", #number(#int(sync.seq))),
          ("did", #string(DID.toText(sync.did))),
          ("blocks", #string("<blob>")), // Blob representation
          ("rev", #string(sync.rev)),
          ("time", #string(sync.time)),
        ]);
      };
      case (#identity(identity)) {
        #object_([
          ("$type", #string("com.atproto.sync.subscribeRepos#identity")),
          ("seq", #number(#int(identity.seq))),
          ("did", #string(DID.toText(identity.did))),
          ("time", #string(identity.time)),
          (
            "handle",
            switch (identity.handle) {
              case (?h) { #string(h) };
              case (null) { #null_ };
            },
          ),
        ]);
      };
      case (#account(account)) {
        let status = switch (account.status) {
          case (?#takendown) { #string("takendown") };
          case (?#suspended) { #string("suspended") };
          case (?#deleted) { #string("deleted") };
          case (?#deactivated) { #string("deactivated") };
          case (?#desynchronized) { #string("desynchronized") };
          case (?#throttled) { #string("throttled") };
          case (null) { #null_ };
        };

        #object_([
          ("$type", #string("com.atproto.sync.subscribeRepos#account")),
          ("seq", #number(#int(account.seq))),
          ("did", #string(DID.toText(account.did))),
          ("time", #string(account.time)),
          ("active", #bool(account.active)),
          ("status", status),
        ]);
      };
      case (#info(info)) {
        let name = switch (info.name) {
          case (#outdatedCursor) { #string("OutdatedCursor") };
        };

        #object_([
          ("$type", #string("com.atproto.sync.subscribeRepos#info")),
          ("name", name),
          (
            "message",
            switch (info.message) {
              case (?m) { #string(m) };
              case (null) { #null_ };
            },
          ),
        ]);
      };
    };
  };

};
