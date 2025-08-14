import Json "mo:json";
import Result "mo:core/Result";
import ActorDefs "./Defs";
import Array "mo:core/Array";
import DynamicArray "mo:xtended-collections/DynamicArray";
import Nat "mo:core/Nat";

module {
  /// Request type for app.bsky.actor.getProfiles
  /// Get detailed profile views of multiple actors.
  public type Request = {
    /// Array of DIDs or handles to fetch profiles for
    actors : [Text]; // maxLength: 25
  };

  /// Response type for app.bsky.actor.getProfiles
  public type Response = {
    profiles : [ActorDefs.ProfileViewDetailed];
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let actorsJson : [Json.Json] = switch (Json.getAsArray(json, "actors")) {
      case (#ok(j)) j;
      case (#err(#pathNotFound)) return #err("Missing required field: actors");
      case (#err(#typeMismatch)) return #err("Invalid actors field: expected array");
    };
    let actorsArray = DynamicArray.DynamicArray<Text>(actorsJson.size());
    var i = 0;
    for (actorJson in actorsJson.vals()) {
      let #string(actorText) = actorJson else return #err("Invalid actor JSON. Expected actors[" # Nat.toText(i) # "] to be string, got: " # debug_show (actorJson));
      actorsArray.add(actorText);
      i += 1;
    };
    #ok({ actors = DynamicArray.toArray(actorsArray) });
  };

  public func toJson(response : Response) : Json.Json {
    let profilesJson = Array.map<ActorDefs.ProfileViewDetailed, Json.Json>(
      response.profiles,
      ActorDefs.profileViewDetailedToJson,
    );
    #object_([("profiles", #array(profilesJson))]);
  };

};
