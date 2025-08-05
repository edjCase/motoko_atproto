import Json "mo:json";
import Result "mo:new-base/Result";

module {

  public type Request = {
    useCount : Int;
    forAccount : ?Text; // DID string
  };

  public type Response = {
    code : Text;
  };

  public func toJson(response : Response) : Json.Json {
    #object_([
      ("code", #string(response.code)),
    ]);
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let useCount = switch (Json.getAsInt(json, "useCount")) {
      case (#ok(count)) count;
      case (#err(#pathNotFound)) return #err("Missing required field: useCount");
      case (#err(#typeMismatch)) return #err("Invalid useCount field, expected integer");
    };

    let forAccount = switch (Json.getAsText(json, "forAccount")) {
      case (#ok(did)) ?did;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid forAccount field, expected string");
    };

    #ok({
      useCount = useCount;
      forAccount = forAccount;
    });
  };

};
