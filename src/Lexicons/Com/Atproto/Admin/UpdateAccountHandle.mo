import Json "mo:json@1";
import Result "mo:core@1/Result";

module {

  /// Request type for com.atproto.admin.updateAccountHandle
  /// Administrative action to update an account's handle.
  public type Request = {
    /// DID of the account to update
    did : Text; // DID string

    /// New handle for the account
    handle : Text; // Handle string
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let did = switch (Json.getAsText(json, "did")) {
      case (#ok(did)) did;
      case (#err(#pathNotFound)) return #err("Missing required field: did");
      case (#err(#typeMismatch)) return #err("Invalid did field, expected string");
    };

    let handle = switch (Json.getAsText(json, "handle")) {
      case (#ok(handle)) handle;
      case (#err(#pathNotFound)) return #err("Missing required field: handle");
      case (#err(#typeMismatch)) return #err("Invalid handle field, expected string");
    };

    #ok({
      did = did;
      handle = handle;
    });
  };

};
