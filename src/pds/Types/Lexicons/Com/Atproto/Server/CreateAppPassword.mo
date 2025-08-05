import Json "mo:json";
import Result "mo:new-base/Result";

module {

  public type AppPassword = {
    name : Text;
    password : Text;
    createdAt : Text;
    privileged : ?Bool;
  };

  public type Request = {
    name : Text;
    privileged : ?Bool;
  };

  public type Response = AppPassword;

  public type Error = {
    #accountTakedown : { message : Text };
  };

  public func toJson(response : Response) : Json.Json {
    let privilegedJson = switch (response.privileged) {
      case (?p) #bool(p);
      case (null) #null_;
    };

    #object_([
      ("name", #string(response.name)),
      ("password", #string(response.password)),
      ("createdAt", #string(response.createdAt)),
      ("privileged", privilegedJson),
    ]);
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let name = switch (Json.getAsText(json, "name")) {
      case (#ok(name)) name;
      case (#err(#pathNotFound)) return #err("Missing required field: name");
      case (#err(#typeMismatch)) return #err("Invalid name field, expected string");
    };

    let privileged = switch (Json.getAsBool(json, "privileged")) {
      case (#ok(p)) ?p;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid privileged field, expected boolean");
    };

    #ok({
      name = name;
      privileged = privileged;
    });
  };

};
