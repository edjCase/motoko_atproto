import DID "mo:did@3";
import PureMap "mo:core@1/pure/Map";
import ActorDefs "../Types/Lexicons/App/Bsky/Actor/Defs";
import Order "mo:core@1/Order";
import Text "mo:core@1/Text";
import Option "mo:core@1/Option";

module {
  public type StableData = {
    preferences : PureMap.Map<DID.Plc.DID, Preferences>;
  };

  public type Preferences = {
    adultContent : ?ActorDefs.AdultContentPref;
    contentLabel : ?ActorDefs.ContentLabelPref;
    savedFeeds : ?ActorDefs.SavedFeedsPref;
    savedFeedsV2 : ?ActorDefs.SavedFeedsPrefV2;
    personalDetails : ?ActorDefs.PersonalDetailsPref;
    feedView : ?ActorDefs.FeedViewPref;
    threadView : ?ActorDefs.ThreadViewPref;
    interests : ?ActorDefs.InterestsPref;
    mutedWords : ?ActorDefs.MutedWordsPref;
    hiddenPosts : ?ActorDefs.HiddenPostsPref;
    bskyAppState : ?ActorDefs.BskyAppStatePref;
    labelers : ?ActorDefs.LabelersPref;
    postInteractionSettings : ?ActorDefs.PostInteractionSettingsPref;
    verification : ?ActorDefs.VerificationPrefs;
  };

  public class Handler(data : StableData) {
    var preferencesMap : PureMap.Map<DID.Plc.DID, Preferences> = data.preferences;

    public func getPreferences(actorId : DID.Plc.DID) : Preferences {
      Option.get(
        PureMap.get(preferencesMap, compareDid, actorId),
        {
          adultContent = null;
          contentLabel = null;
          savedFeeds = null;
          savedFeedsV2 = null;
          personalDetails = null;
          feedView = null;
          threadView = null;
          interests = null;
          mutedWords = null;
          hiddenPosts = null;
          bskyAppState = null;
          labelers = null;
          postInteractionSettings = null;
          verification = null;
        },
      );
    };

    public func putPreferences(
      actorId : DID.Plc.DID,
      newPreferences : [ActorDefs.PreferenceItem],
    ) : () {
      if (newPreferences.size() == 0) {
        return;
      };
      var preferences : Preferences = getPreferences(actorId);
      for (preference in newPreferences.vals()) {
        preferences := switch (preference) {
          case (#adultContentPref(p)) ({ preferences with adultContent = ?p });
          case (#contentLabelPref(p)) ({ preferences with contentLabel = ?p });
          case (#savedFeedsPref(p)) ({ preferences with savedFeeds = ?p });
          case (#savedFeedsPrefV2(p)) ({ preferences with savedFeedsV2 = ?p });
          case (#personalDetailsPref(p)) ({
            preferences with personalDetails = ?p
          });
          case (#feedViewPref(p)) ({ preferences with feedView = ?p });
          case (#threadViewPref(p)) ({ preferences with threadView = ?p });
          case (#interestsPref(p)) ({ preferences with interests = ?p });
          case (#mutedWordsPref(p)) ({ preferences with mutedWords = ?p });
          case (#hiddenPostsPref(p)) ({ preferences with hiddenPosts = ?p });
          case (#bskyAppStatePref(p)) ({ preferences with bskyAppState = ?p });
          case (#labelersPref(p)) ({ preferences with labelers = ?p });
          case (#postInteractionSettingsPref(p)) ({
            preferences with postInteractionSettings = ?p
          });
          case (#verificationPrefs(p)) ({ preferences with verification = ?p });
        };
      };
      preferencesMap := PureMap.add(preferencesMap, compareDid, actorId, preferences);
    };

    public func toStableData() : StableData {
      {
        preferences = preferencesMap;
      };
    };
  };

  // TODO build into DID library?
  func compareDid(a : DID.Plc.DID, b : DID.Plc.DID) : Order.Order {
    return Text.compare(a.identifier, b.identifier);
  };
};
