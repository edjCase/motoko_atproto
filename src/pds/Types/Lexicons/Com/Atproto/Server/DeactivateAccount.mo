import Json "mo:json";
import Result "mo:new-base/Result";

module {

  public type Request = {
    deleteAfter : ?Text; // datetime string
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let deleteAfter = switch (Json.getAsText(json, "deleteAfter")) {
      case (#ok(dt)) ?dt;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid deleteAfter field, expected string");
    };

    #ok({
      deleteAfter = deleteAfter;
    });
  };

};
