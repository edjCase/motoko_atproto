import DagCbor "mo:dag-cbor@2";
import Json "mo:json@1";
import Result "mo:core@1/Result";
import Array "mo:core@1/Array";
import JsonDagCborMapper "../../../../JsonDagCborMapper";

module {

  /// Request type for com.atproto.identity.signPlcOperation
  public type Request = {
    /// A token received through com.atproto.identity.requestPlcOperationSignature
    token : ?Text;

    /// Rotation keys for the DID
    rotationKeys : ?[Text];

    /// Also known as identifiers
    alsoKnownAs : ?[Text];

    /// Verification methods (type unknown in schema)
    verificationMethods : ?DagCbor.Value;

    /// Services (type unknown in schema)
    services : ?DagCbor.Value;
  };

  /// Response type for com.atproto.identity.signPlcOperation
  public type Response = {
    /// A signed DID PLC operation
    operation : DagCbor.Value;
  };

  public func toJson(response : Response) : Json.Json {
    let operationJson = JsonDagCborMapper.fromDagCbor(response.operation);

    #object_([
      ("operation", operationJson),
    ]);
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    // Extract optional fields
    let token = switch (Json.getAsText(json, "token")) {
      case (#ok(token)) ?token;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid token field, expected string");
    };

    let rotationKeys = switch (Json.getAsArray(json, "rotationKeys")) {
      case (#ok(arr)) {
        let keys = Array.mapFilter<Json.Json, Text>(
          arr,
          func(item) {
            switch (item) {
              case (#string(s)) ?s;
              case (_) null;
            };
          },
        );
        if (keys.size() == arr.size()) ?keys else return #err("Invalid rotationKeys array, expected string items");
      };
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid rotationKeys field, expected array");
    };

    let alsoKnownAs = switch (Json.getAsArray(json, "alsoKnownAs")) {
      case (#ok(arr)) {
        let items = Array.mapFilter<Json.Json, Text>(
          arr,
          func(item) {
            switch (item) {
              case (#string(s)) ?s;
              case (_) null;
            };
          },
        );
        if (items.size() == arr.size()) ?items else return #err("Invalid alsoKnownAs array, expected string items");
      };
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid alsoKnownAs field, expected array");
    };

    let verificationMethods = switch (Json.get(json, "verificationMethods")) {
      case (?vm) ?JsonDagCborMapper.toDagCbor(vm);
      case (null) null;
    };

    let services = switch (Json.get(json, "services")) {
      case (?s) ?JsonDagCborMapper.toDagCbor(s);
      case (null) null;
    };

    #ok({
      token = token;
      rotationKeys = rotationKeys;
      alsoKnownAs = alsoKnownAs;
      verificationMethods = verificationMethods;
      services = services;
    });
  };
};
