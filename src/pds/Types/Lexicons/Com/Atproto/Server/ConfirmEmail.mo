import Json "mo:json";
import Result "mo:new-base/Result";

module {

  public type Request = {
    email : Text;
    token : Text;
  };

  public type Error = {
    #accountNotFound : { message : Text };
    #expiredToken : { message : Text };
    #invalidToken : { message : Text };
    #invalidEmail : { message : Text };
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let email = switch (Json.getAsText(json, "email")) {
      case (#ok(email)) email;
      case (#err(#pathNotFound)) return #err("Missing required field: email");
      case (#err(#typeMismatch)) return #err("Invalid email field, expected string");
    };

    let token = switch (Json.getAsText(json, "token")) {
      case (#ok(token)) token;
      case (#err(#pathNotFound)) return #err("Missing required field: token");
      case (#err(#typeMismatch)) return #err("Invalid token field, expected string");
    };

    #ok({
      email = email;
      token = token;
    });
  };

};
