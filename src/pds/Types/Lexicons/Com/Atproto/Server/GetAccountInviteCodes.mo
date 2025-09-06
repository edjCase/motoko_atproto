import Json "mo:json@1";
import Result "mo:core@1/Result";
import Array "mo:base/Array";
import Defs "./Defs";

module {

  public type Request = {
    includeUsed : ?Bool;
    createAvailable : ?Bool;
  };

  public type Response = {
    codes : [Defs.InviteCode];
  };

  public type Error = {
    #duplicateCreate : { message : Text };
  };

  public func toJson(response : Response) : Json.Json {
    let codesJson = response.codes |> Array.map<Defs.InviteCode, Json.Json>(_, Defs.inviteCodeToJson);

    #object_([
      ("codes", #array(codesJson)),
    ]);
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let includeUsed = switch (Json.getAsBool(json, "includeUsed")) {
      case (#ok(iu)) ?iu;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid includeUsed field, expected boolean");
    };

    let createAvailable = switch (Json.getAsBool(json, "createAvailable")) {
      case (#ok(ca)) ?ca;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid createAvailable field, expected boolean");
    };

    #ok({
      includeUsed = includeUsed;
      createAvailable = createAvailable;
    });
  };

};
