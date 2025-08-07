import DID "mo:did";
import CID "mo:cid";
import TID "mo:tid";
import DagCbor "mo:dag-cbor";
import AtUri "../../../../AtUri";
import Json "mo:json";
import Result "mo:core/Result";
import JsonDagCborMapper "../../../../../JsonDagCborMapper";

module {

  /// Request type for getting a single repository record
  public type Request = {
    /// The handle or DID of the repo
    repo : DID.Plc.DID;

    /// The NSID of the record collection
    collection : Text;

    /// The Record Key
    rkey : Text;

    /// The CID of the version of the record. If not provided, returns the most recent version
    cid : ?CID.CID;
  };

  /// Response from a successful record retrieval
  public type Response = {
    /// AT-URI identifying the retrieved record
    uri : AtUri.AtUri;

    /// Content Identifier of the retrieved record
    cid : ?CID.CID;

    /// The record data
    value : DagCbor.Value;
  };

  public func toJson(response : Response) : Json.Json {

    let atUri = AtUri.toText(response.uri);
    let valueJson = JsonDagCborMapper.fromDagCbor(response.value);
    #object_([
      ("uri", #string(atUri)),
      (
        "cid",
        switch (response.cid) {
          case (?cid) #string(CID.toText(cid));
          case (null) #null_;
        },
      ),
      ("value", valueJson),
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

    let cid = switch (Json.getAsText(json, "cid")) {
      case (#ok(s)) switch (CID.fromText(s)) {
        case (#ok(cid)) ?cid;
        case (#err(e)) return #err("Invalid cid: " # e);
      };
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid cid field, expected string");
    };

    #ok({
      repo = repo;
      collection = collection;
      rkey = rkey;
      cid = cid;
    });
  };

};
