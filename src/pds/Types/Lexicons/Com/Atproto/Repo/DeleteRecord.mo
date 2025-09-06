import DID "mo:did@2";
import CID "mo:cid@1";
import TID "mo:tid@1";
import DagCbor "mo:dag-cbor@2";
import AtUri "../../../../AtUri";
import Json "mo:json@1";
import Result "mo:core@1/Result";
import Common "./Common";

module {

  /// Request type for deleting a repository record
  public type Request = {
    /// The handle or DID of the repo (aka, current account)
    repo : DID.Plc.DID;

    /// The NSID of the record collection
    collection : Text;

    /// The Record Key
    rkey : Text;

    /// Compare and swap with the previous record by CID
    swapRecord : ?CID.CID;

    /// Compare and swap with the previous commit by CID
    swapCommit : ?CID.CID;
  };

  /// Response from a successful record deletion
  public type Response = {
    /// Optional metadata about the repository commit that included this deletion
    commit : ?Common.CommitMeta;
  };

  public func toJson(response : Response) : Json.Json {

    #object_([
      (
        "commit",
        switch (response.commit) {
          case (?commit) #object_([
            ("cid", #string(CID.toText(commit.cid))),
            ("rev", #string(TID.toText(commit.rev))),
          ]);
          case (null) #null_;
        },
      ),
    ]);
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {

    // Extract required fields

    let repoText = switch (Json.getAsText(json, "repo")) {
      case (#ok(repo)) repo;
      case (#err(#pathNotFound)) return #err("Missing required field: repo");
      case (#err(#typeMismatch)) return #err("Invalid repo field, expected string");
    };
    let repo = switch (DID.Plc.fromText(repoText)) {
      case (#ok(did)) did;
      case (#err(e)) return #err("Invalid repo DID: " # e);
    };

    let collection = switch (Json.getAsText(json, "collection")) {
      case (#ok(collection)) collection;
      case (#err(#pathNotFound)) return #err("Missing required field: collection");
      case (#err(#typeMismatch)) return #err("Invalid collection field, expected string");
    };

    let rkey = switch (Json.getAsText(json, "rkey")) {
      case (#ok(rkey)) rkey;
      case (#err(#pathNotFound)) return #err("Missing required field: rkey");
      case (#err(#typeMismatch)) return #err("Invalid rkey field, expected string");
    };

    // Extract optional fields

    let swapRecord = switch (Json.getAsText(json, "swapRecord")) {
      case (#ok(s)) switch (CID.fromText(s)) {
        case (#ok(cid)) ?cid;
        case (#err(e)) return #err("Invalid swapRecord CID: " # e);
      };
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid swapRecord field, expected string");
    };

    let swapCommit = switch (Json.getAsText(json, "swapCommit")) {
      case (#ok(s)) switch (CID.fromText(s)) {
        case (#ok(cid)) ?cid;
        case (#err(e)) return #err("Invalid swapCommit CID: " # e);
      };
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid swapCommit field, expected string");
    };

    #ok({
      repo = repo;
      collection = collection;
      rkey = rkey;
      swapRecord = swapRecord;
      swapCommit = swapCommit;
    });
  };
};
