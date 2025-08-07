import DID "mo:did";
import CID "mo:cid";
import TID "mo:tid";
import DagCbor "mo:dag-cbor";
import AtUri "../../../../AtUri";
import Json "mo:json";
import Common "./Common";
import Result "mo:core/Result";
import JsonDagCborMapper "../../../../../JsonDagCborMapper";

module {

  /// Request type for creating a single new repository record
  public type Request = {
    /// The handle or DID of the repo (aka, current account)
    repo : DID.Plc.DID;

    /// The NSID of the record collection (e.g., "app.bsky.feed.post")
    collection : Text;

    /// The Record Key. Optional - if not provided, system will generate one.
    /// Maximum length: 512 characters
    rkey : ?Text;

    /// The record itself. Must contain a $type field that matches the collection NSID
    record : DagCbor.Value;

    /// Schema validation setting:
    /// - true: require Lexicon schema validation
    /// - false: skip Lexicon schema validation
    /// - null: validate only for known Lexicons (default behavior)
    validate : ?Bool;

    /// Compare and swap with the previous commit by CID.
    /// Used for atomic updates - operation fails if repo state has changed
    swapCommit : ?CID.CID;
  };

  /// Response from a successful record creation
  public type Response = {
    /// AT-URI identifying the created record
    uri : AtUri.AtUri;

    /// Content Identifier of the created record
    cid : CID.CID;

    /// Optional metadata about the repository commit that included this record
    commit : ?Common.CommitMeta;

    /// Validation status of the created record against its Lexicon schema
    validationStatus : Common.ValidationStatus;
  };

  public func toJson(response : Response) : Json.Json {

    let atUri = AtUri.toText(response.uri);
    let cidText = CID.toText(response.cid);

    let validationStatusText = switch (response.validationStatus) {
      case (#valid) "valid";
      case (#unknown) "unknown";
    };

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
      ("validationStatus", #string(validationStatusText)),
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

    let recordJson = switch (Json.get(json, "record")) {
      case (?record) record;
      case (null) return #err("Missing required field: record");
    };

    let recordDagCbor = JsonDagCborMapper.toDagCbor(recordJson);

    // Extract optional fields

    let rkey = switch (Json.getAsText(json, "rkey")) {
      case (#ok(rkey)) ?rkey;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid rkey field, expected string");
    };

    let validate = switch (Json.getAsBool(json, "validate")) {
      case (#ok(validate)) ?validate;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid validate field, expected boolean");
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
      record = recordDagCbor;
      validate = validate;
      swapCommit = swapCommit;
    });
  };
};
