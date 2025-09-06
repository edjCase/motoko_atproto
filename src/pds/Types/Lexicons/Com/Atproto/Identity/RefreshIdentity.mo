import DID "mo:did@2";
import Json "mo:json@1";
import Result "mo:core@1/Result";
import Defs "./Defs";

module {

  /// Request type for com.atproto.identity.refreshIdentity
  public type Request = {
    /// The identifier (handle or DID) to refresh
    identifier : Text;
  };

  /// Response type for com.atproto.identity.refreshIdentity
  public type Response = Defs.IdentityInfo;

  /// Error types that can be returned by this endpoint
  public type Error = {
    #handleNotFound : { message : Text };
    #didNotFound : { message : Text };
    #didDeactivated : { message : Text };
  };

  public func toJson(response : Response) : Json.Json {
    Defs.identityInfoToJson(response);
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let identifier = switch (Json.getAsText(json, "identifier")) {
      case (#ok(identifier)) identifier;
      case (#err(#pathNotFound)) return #err("Missing required field: identifier");
      case (#err(#typeMismatch)) return #err("Invalid identifier field, expected string");
    };

    #ok({
      identifier = identifier;
    });
  };
};
