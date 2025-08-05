import Json "mo:json";
import Result "mo:new-base/Result";

module {

  /// Request type for com.atproto.identity.updateHandle
  public type Request = {
    /// The new handle
    handle : Text;
  };

  /// This endpoint has no response output (just updates the handle)

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
