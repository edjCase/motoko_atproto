import DID "mo:did@3";
import CID "mo:cid@1";
import TID "mo:tid@1";
import DagCbor "mo:dag-cbor@2";
import AtUri "../../../../AtUri";
import Json "mo:json@1";
import Result "mo:core@1/Result";
import Common "./Common";
import JsonDagCborMapper "../../../../JsonDagCborMapper";

module {

  /// Request type for creating or updating a repository record
  public type Request = {
    /// The handle or DID of the repo (aka, current account)
    repo : DID.Plc.DID;

    /// The NSID of the record collection
    collection : Text;

    /// The Record Key. Maximum length: 512 characters
    rkey : Text;

    /// Schema validation setting:
    /// - true: require Lexicon schema validation
    /// - false: skip Lexicon schema validation
    /// - null: validate only for known Lexicons (default behavior)
    validate : ?Bool;

    /// The record to write
    record : DagCbor.Value;

    /// Compare and swap with the previous record by CID
    swapRecord : ?CID.CID;

    /// Compare and swap with the previous commit by CID
    swapCommit : ?CID.CID;
  };

  /// Response from a successful record put operation
  public type Response = {
    /// AT-URI identifying the record
    uri : AtUri.AtUri;

    /// Content Identifier of the record
    cid : CID.CID;

    /// Optional metadata about the repository commit that included this record
    commit : ?Common.CommitMeta;

    /// Validation status of the record against its Lexicon schema
    validationStatus : ?Common.ValidationStatus;
  };

  public func toJson(response : Response) : Json.Json {

    let atUri = AtUri.toText(response.uri);
    let cidText = CID.toText(response.cid);

    #object_([
      ("uri", #string(atUri)),
      ("cid", #string(cidText)),
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
      (
        "validationStatus",
        switch (response.validationStatus) {
          case (?status) switch (status) {
            case (#valid) #string("valid");
            case (#unknown) #string("unknown");
          };
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

    let recordJson = switch (Json.get(json, "record")) {
      case (?record) record;
      case (null) return #err("Missing required field: record");
    };

    let recordDagCbor = JsonDagCborMapper.toDagCbor(recordJson);

    // Extract optional fields

    let validate = switch (Json.getAsBool(json, "validate")) {
      case (#ok(validate)) ?validate;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid validate field, expected boolean");
    };

    let swapRecord = switch (Json.get(json, "swapRecord")) {
      case (?#string(s)) switch (CID.fromText(s)) {
        case (#ok(cid)) ?cid;
        case (#err(e)) return #err("Invalid swapRecord CID: " # e);
      };
      case (null or ?#null_) null;
      case (?j) return #err("Invalid swapRecord field, expected string, got: " # debug_show (j));
    };

    let swapCommit = switch (Json.get(json, "swapCommit")) {
      case (?#string(s)) switch (CID.fromText(s)) {
        case (#ok(cid)) ?cid;
        case (#err(e)) return #err("Invalid swapCommit CID: " # e);
      };
      case (null or ?#null_) null;
      case (?j) return #err("Invalid swapCommit field, expected string, got: " # debug_show (j));
    };

    #ok({
      repo = repo;
      collection = collection;
      rkey = rkey;
      validate = validate;
      record = recordDagCbor;
      swapRecord = swapRecord;
      swapCommit = swapCommit;
    });
  };
};
