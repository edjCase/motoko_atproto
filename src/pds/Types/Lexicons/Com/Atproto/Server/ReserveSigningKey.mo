import Json "mo:json";
import DID "mo:did";

module {
  // com.atproto.server.reserveSigningKey
  // Reserve a repo signing key, for use with account creation. Necessary so that a DID PLC update operation can be constructed during an account migraiton. Public and does not require auth; implemented by PDS. NOTE: this endpoint may change when full account migration is implemented.

  public type Request = {
    did : ?DID.DID;
  };

  public type Response = {
    signingKey : Text;
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let didText = switch (Json.getAsText(json, "did")) {
      case (#ok(s)) s;
      case (#err(#pathNotFound)) return {
        did = null;
      };
      case (#err(#typeMismatch)) return #err("Invalid did field, expected string");
    };

    let did = switch (DID.fromText(didText)) {
      case (#ok(did)) did;
      case (#err(_)) return #err("Invalid DID format");
    };
    #ok({
      did = ?did;
    });
  };

  public func toJson(response : Response) : Json.Json {
    #object_([("signingKey", #string(response.signingKey))]);
  };

};
