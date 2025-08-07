import Json "mo:json";
import Result "mo:core/Result";

module {

  /// Request type for com.atproto.admin.updateAccountSigningKey
  /// Administrative action to update an account's signing key in their Did document.
  public type Request = {
    /// DID of the account to update signing key for
    did : Text; // DID string

    /// Did-key formatted public key
    signingKey : Text; // DID string
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let did = switch (Json.getAsText(json, "did")) {
      case (#ok(did)) did;
      case (#err(#pathNotFound)) return #err("Missing required field: did");
      case (#err(#typeMismatch)) return #err("Invalid did field, expected string");
    };

    let signingKey = switch (Json.getAsText(json, "signingKey")) {
      case (#ok(signingKey)) signingKey;
      case (#err(#pathNotFound)) return #err("Missing required field: signingKey");
      case (#err(#typeMismatch)) return #err("Invalid signingKey field, expected string");
    };

    #ok({
      did = did;
      signingKey = signingKey;
    });
  };

};
