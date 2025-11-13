import Json "mo:json@1";
import Result "mo:core@1/Result";
import ActorDefs "./Defs";

module {
  /// Response type for app.bsky.actor.getPreferences
  public type Response = {
    preferences : ActorDefs.Preferences;
  };

  /// Convert response to JSON
  public func toJson(response : Response) : Json.Json {
    #object_([
      ("preferences", ActorDefs.preferencesToJson(response.preferences)),
    ]);
  };

};
