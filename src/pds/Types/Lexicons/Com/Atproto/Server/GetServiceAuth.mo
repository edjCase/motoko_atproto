import Json "mo:json";
import Result "mo:core/Result";

module {

  public type Request = {
    aud : Text; // DID string
    exp : ?Int;
    lxm : ?Text; // NSID string
  };

  public type Response = {
    token : Text;
  };

  public type Error = {
    #badExpiration : { message : Text };
  };

  public func toJson(response : Response) : Json.Json {
    #object_([
      ("token", #string(response.token)),
    ]);
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let aud = switch (Json.getAsText(json, "aud")) {
      case (#ok(aud)) aud;
      case (#err(#pathNotFound)) return #err("Missing required field: aud");
      case (#err(#typeMismatch)) return #err("Invalid aud field, expected string");
    };

    let exp = switch (Json.getAsInt(json, "exp")) {
      case (#ok(exp)) ?exp;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid exp field, expected integer");
    };

    let lxm = switch (Json.getAsText(json, "lxm")) {
      case (#ok(lxm)) ?lxm;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid lxm field, expected string");
    };

    #ok({
      aud = aud;
      exp = exp;
      lxm = lxm;
    });
  };

};
