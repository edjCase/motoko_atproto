import Json "mo:json@1";
import Result "mo:core@1/Result";
import ActorDefs "./Defs";

module {

  /// Request type for app.bsky.actor.getProfile
  /// Get detailed profile view of an actor.
  public type Request = {
    /// Handle or DID of account to fetch profile of
    actorDid : Text; // Handle or DID string
  };

  /// Response type for app.bsky.actor.getProfile
  public type Response = ActorDefs.ProfileViewDetailed;

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let actorDid = switch (Json.getAsText(json, "actor")) {
      case (#ok(actorDid)) actorDid;
      case (#err(#pathNotFound)) return #err("Missing required field: actor");
      case (#err(#typeMismatch)) return #err("Invalid actor field, expected string");
    };

    #ok({
      actorDid = actorDid;
    });
  };

  public func toJson(response : Response) : Json.Json {
    ActorDefs.profileViewDetailedToJson(response);
  };

};
