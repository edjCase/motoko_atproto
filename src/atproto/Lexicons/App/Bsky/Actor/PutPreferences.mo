import Json "mo:json@1";
import Result "mo:core@1/Result";
import ActorDefs "./Defs";

module {
  /// Request type for app.bsky.actor.putPreferences
  public type Request = {
    preferences : ActorDefs.Preferences;
  };

  /// Convert response to JSON
  public func fromJson(response : Json.Json) : Result.Result<Request, Text> {
    let ?preferencesJson = Json.get(response, "preferences") else return #err("Missing required field: preferences");
    let preferences = switch (ActorDefs.preferencesFromJson(preferencesJson)) {
      case (#ok(p)) p;
      case (#err(e)) return #err("Invalid preferences field: " # e);
    };
    #ok({
      preferences = preferences;
    });
  };

};
