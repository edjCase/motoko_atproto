import DID "mo:did@2";
import Json "mo:json@1";
import Result "mo:core@1/Result";

module {

  /// Request type for com.atproto.identity.resolveHandle
  public type Request = {
    /// The handle to resolve
    handle : Text;
  };

  /// Response type for com.atproto.identity.resolveHandle
  public type Response = {
    /// The resolved DID
    did : DID.Plc.DID;
  };

  /// Error types that can be returned by this endpoint
  public type Error = {
    #handleNotFound : { message : Text };
  };

  public func toJson(response : Response) : Json.Json {
    let didText = DID.Plc.toText(response.did);

    #object_([
      ("did", #string(didText)),
    ]);
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let handle = switch (Json.getAsText(json, "handle")) {
      case (#ok(handle)) handle;
      case (#err(#pathNotFound)) return #err("Missing required field: handle");
      case (#err(#typeMismatch)) return #err("Invalid handle field, expected string");
    };

    #ok({
      handle = handle;
    });
  };
};
