import Json "mo:json@1";
import Result "mo:core@1/Result";

module {

  /// Request type for com.atproto.admin.deleteAccount
  /// Delete a user account as an administrator.
  public type Request = {
    /// DID of the account to delete
    did : Text; // DID string
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let did = switch (Json.getAsText(json, "did")) {
      case (#ok(did)) did;
      case (#err(#pathNotFound)) return #err("Missing required field: did");
      case (#err(#typeMismatch)) return #err("Invalid did field, expected string");
    };

    #ok({
      did = did;
    });
  };

};
