import Json "mo:json";
import Result "mo:new-base/Result";
import AdminDefs "./Defs";

module {

  /// Request type for com.atproto.admin.getAccountInfo
  /// Get details about an account.
  public type Request = {
    /// DID of the account to get info for
    did : Text; // DID string
  };

  /// Response type for com.atproto.admin.getAccountInfo
  public type Response = AdminDefs.AccountView;

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

  public func toJson(response : Response) : Json.Json {
    AdminDefs.accountViewToJson(response);
  };

};
