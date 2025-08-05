import Json "mo:json";

module {
  // com.atproto.server.revokeAppPassword
  // Revoke an App Password by name.

  public type Request = {
    name : Text;
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let name = switch (Json.getAsText(json, "name")) {
      case (#ok(n)) n;
      case (#err(#pathNotFound)) return #err("Missing required field: name");
      case (#err(#typeMismatch)) return #err("Invalid name field, expected string");
    };
    #ok({
      name = name;
    });
  };

};
