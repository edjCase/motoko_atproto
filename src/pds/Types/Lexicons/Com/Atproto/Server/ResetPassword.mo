import Json "mo:json@1";
import Result "mo:core@1/Result";

module {
  // com.atproto.server.resetPassword
  // Reset a user account password using a token.

  public type Request = {
    token : Text;
    password : Text;
  };

  public type Error = {
    #expiredToken;
    #invalidToken;
  };

  public type Response = Result.Result<(), Error>;

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let token = switch (Json.getAsText(json, "token")) {
      case (#ok(t)) t;
      case (#err(#pathNotFound)) return #err("Missing required field: token");
      case (#err(#typeMismatch)) return #err("Invalid token field, expected string");
    };
    let password = switch (Json.getAsText(json, "password")) {
      case (#ok(p)) p;
      case (#err(#pathNotFound)) return #err("Missing required field: password");
      case (#err(#typeMismatch)) return #err("Invalid password field, expected string");
    };
    #ok({
      token = token;
      password = password;
    });
  };

};
