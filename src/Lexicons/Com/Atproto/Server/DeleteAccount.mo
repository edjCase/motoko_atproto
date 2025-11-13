import Json "mo:json@1";
import Result "mo:core@1/Result";

module {

  public type Request = {
    did : Text; // DID string
    password : Text;
    token : Text;
  };

  public type Error = {
    #expiredToken : { message : Text };
    #invalidToken : { message : Text };
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let did = switch (Json.getAsText(json, "did")) {
      case (#ok(did)) did;
      case (#err(#pathNotFound)) return #err("Missing required field: did");
      case (#err(#typeMismatch)) return #err("Invalid did field, expected string");
    };

    let password = switch (Json.getAsText(json, "password")) {
      case (#ok(password)) password;
      case (#err(#pathNotFound)) return #err("Missing required field: password");
      case (#err(#typeMismatch)) return #err("Invalid password field, expected string");
    };

    let token = switch (Json.getAsText(json, "token")) {
      case (#ok(token)) token;
      case (#err(#pathNotFound)) return #err("Missing required field: token");
      case (#err(#typeMismatch)) return #err("Invalid token field, expected string");
    };

    #ok({
      did = did;
      password = password;
      token = token;
    });
  };

};
