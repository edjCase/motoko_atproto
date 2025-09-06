import Json "mo:json@1";
import Result "mo:base/Result";

module {
  // com.atproto.server.updateEmail
  // Update an account's email.

  public type Request = {
    email : Text;
    emailAuthFactor : ?Bool;
    token : ?Text;
  };

  public type Error = {
    #expiredToken;
    #invalidToken;
    #tokenRequired;
  };

  public type Response = Result.Result<(), Error>;

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let email = switch (Json.getAsText(json, "email")) {
      case (#ok(e)) e;
      case (#err(#pathNotFound)) return #err("Missing required field: email");
      case (#err(#typeMismatch)) return #err("Invalid email field, expected string");
    };
    let emailAuthFactor = switch (Json.getAsBool(json, "emailAuthFactor")) {
      case (#ok(b)) ?b;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid emailAuthFactor field, expected boolean");
    };
    let tokenOrNull = switch (Json.getAsText(json, "token")) {
      case (#ok(t)) ?t;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid token field, expected string");
    };
    #ok({
      email = email;
      emailAuthFactor = emailAuthFactor;
      token = tokenOrNull;
    });
  };

};
