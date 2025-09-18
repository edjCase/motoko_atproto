import Json "mo:json@1";
import Array "mo:core@1/Array";
import Result "mo:core@1/Result";
import Int "mo:core@1/Int";
import DID "mo:did@3";
import AtUri "../../../../AtUri";
import DateTime "mo:datetime@1/DateTime";
import LabelDefs "../../../Com/Atproto/Label/Defs";
import DynamicArray "mo:xtended-collections@0/DynamicArray";
import Time "mo:core@1/Time";

module {

  /// Basic profile view with essential information
  public type ProfileViewBasic = {
    /// DID of the actor
    did : DID.Plc.DID; // DID

    /// Handle of the actor
    handle : Text; // Handle string

    /// Optional display name
    displayName : ?Text;

    /// Optional avatar image
    avatar : ?Text; // URI

    /// Creation timestamp
    createdAt : ?Time.Time;

    /// Labels applied to this profile
    labels : [LabelDefs.Label];

    /// Profile associations (optional)
    associated : ?ProfileAssociated;

    /// Viewer state (optional)
    viewer : ?ViewerState;

    /// Verification state (optional)
    verification : ?VerificationState;

    /// Status view (optional)
    status : ?StatusView;
  };

  /// Standard profile view with additional details
  public type ProfileView = ProfileViewBasic and {
    /// Optional bio/description
    description : ?Text;

    /// Index timestamp
    indexedAt : ?Time.Time;
  };

  /// Detailed profile view with complete information
  public type ProfileViewDetailed = ProfileView and {
    /// Optional banner image
    banner : ?Text; // URI

    /// Number of followers
    followersCount : ?Nat;

    /// Number of accounts following
    followsCount : ?Nat;

    /// Number of posts
    postsCount : ?Nat;

    /// Joined via starter pack (optional)
    joinedViaStarterPack : ?Text; // Reference to starter pack - simplified as Text for now

    /// Pinned post (optional)
    pinnedPost : ?Text; // Reference to strong ref - simplified as Text for now
  };

  /// Profile association information
  public type ProfileAssociated = {
    lists : ?Nat;
    feedgens : ?Nat;
    starterPacks : ?Nat;
    labeler : ?Bool;
    chat : ?ProfileAssociatedChat;
    activitySubscription : ?ProfileAssociatedActivitySubscription;
  };

  /// Profile associated chat settings
  public type ProfileAssociatedChat = {
    allowIncoming : { #all; #none; #following };
  };

  /// Profile associated activity subscription settings
  public type ProfileAssociatedActivitySubscription = {
    allowSubscriptions : { #followers; #mutuals; #none };
  };

  /// Viewer state relative to the profile
  public type ViewerState = {
    muted : ?Bool;
    mutedByList : ?Text; // Reference to list - simplified as Text for now
    blockedBy : ?Bool;
    blocking : ?AtUri.AtUri;
    blockingByList : ?Text; // Reference to list - simplified as Text for now
    following : ?AtUri.AtUri;
    followedBy : ?AtUri.AtUri;
    knownFollowers : ?KnownFollowers;
    activitySubscription : ?Text; // Reference to activity subscription - simplified as Text for now
  };

  /// Known followers information
  public type KnownFollowers = {
    count : Nat;
    followers : [ProfileViewBasic]; // Max 5 items
  };

  /// Verification state information
  public type VerificationState = {
    verifications : [VerificationView];
    verifiedStatus : { #valid; #invalid; #none };
    trustedVerifierStatus : { #valid; #invalid; #none };
  };

  /// Individual verification view
  public type VerificationView = {
    issuer : DID.Plc.DID;
    uri : AtUri.AtUri;
    isValid : Bool;
    createdAt : Time.Time;
  };

  /// Status view information
  public type StatusView = {
    status : Text; // Known value: "app.bsky.actor.status#live"
    record : Json.Json; // Unknown type - using Json for flexibility
    embed : ?Text; // Reference to embed - simplified as Text for now
    expiresAt : ?Time.Time;
    isActive : ?Bool;
  };

  // Helper function to add basic profile fields that are common to all profile types
  private func addBasicProfileFields(fields : DynamicArray.DynamicArray<(Text, Json.Json)>, profile : ProfileViewBasic) : () {
    let labelsJson = Array.map<LabelDefs.Label, Json.Json>(profile.labels, LabelDefs.labelToJson);

    fields.add(("did", #string(DID.Plc.toText(profile.did))));
    fields.add(("handle", #string(profile.handle)));
    fields.add(("labels", #array(labelsJson)));

    switch (profile.displayName) {
      case (?displayName) fields.add(("displayName", #string(displayName)));
      case (null) ();
    };

    switch (profile.avatar) {
      case (?avatar) fields.add(("avatar", #string(avatar)));
      case (null) ();
    };

    switch (profile.createdAt) {
      case (?createdAt) fields.add(("createdAt", #string(DateTime.DateTime(createdAt).toText())));
      case (null) ();
    };
  };

  // Helper function to add ProfileView fields (includes basic fields + ProfileView-specific fields)
  private func addProfileViewFields(fields : DynamicArray.DynamicArray<(Text, Json.Json)>, profile : ProfileView) : () {
    // Add basic fields first
    addBasicProfileFields(fields, profile);

    // Add ProfileView-specific fields
    switch (profile.description) {
      case (?description) fields.add(("description", #string(description)));
      case (null) ();
    };

    switch (profile.indexedAt) {
      case (?indexedAt) fields.add(("indexedAt", #string(DateTime.DateTime(indexedAt).toText())));
      case (null) ();
    };
  };

  public func profileViewBasicToJson(profile : ProfileViewBasic) : Json.Json {
    let fields = DynamicArray.DynamicArray<(Text, Json.Json)>(10);
    addBasicProfileFields(fields, profile);
    #object_(DynamicArray.toArray(fields));
  };

  public func profileViewToJson(profile : ProfileView) : Json.Json {
    let fields = DynamicArray.DynamicArray<(Text, Json.Json)>(12);
    addProfileViewFields(fields, profile);
    #object_(DynamicArray.toArray(fields));
  };
  public func profileViewDetailedToJson(profile : ProfileViewDetailed) : Json.Json {
    let fields = DynamicArray.DynamicArray<(Text, Json.Json)>(15);

    // Add ProfileView fields using helper (includes basic + ProfileView fields)
    addProfileViewFields(fields, profile);

    // Add ProfileViewDetailed-specific fields
    switch (profile.banner) {
      case (?banner) fields.add(("banner", #string(banner)));
      case (null) ();
    };

    switch (profile.followersCount) {
      case (?followersCount) fields.add(("followersCount", #number(#int(followersCount))));
      case (null) ();
    };

    switch (profile.followsCount) {
      case (?followsCount) fields.add(("followsCount", #number(#int(followsCount))));
      case (null) ();
    };

    switch (profile.postsCount) {
      case (?postsCount) fields.add(("postsCount", #number(#int(postsCount))));
      case (null) ();
    };

    #object_(DynamicArray.toArray(fields));
  };

  // Preference types
  public type AdultContentPref = {
    enabled : Bool;
  };

  public type ContentLabelPref = {
    labelerDid : ?DID.DID; // DID
    label_ : Text;
    visibility : ContentVisibility;
  };

  public type ContentVisibility = {
    #ignore_;
    #show;
    #warn;
    #hide;
  };

  public type SavedFeed = {
    id : Text;
    type_ : { #feed; #list; #timeline };
    value : Text;
    pinned : Bool;
  };

  public type SavedFeedsPrefV2 = {
    items : [SavedFeed];
  };

  public type SavedFeedsPref = {
    pinned : [AtUri.AtUri];
    saved : [AtUri.AtUri];
    timelineIndex : ?Nat;
  };

  public type PersonalDetailsPref = {
    birthDate : ?Text; // datetime
  };

  public type FeedViewPref = {
    feed : Text; // URI of the feed
    hideReplies : ?Bool;
    hideRepliesByUnfollowed : ?Bool;
    hideRepliesByLikeCount : ?Nat;
    hideReposts : ?Bool;
    hideQuotePosts : ?Bool;
  };

  public type ThreadViewPref = {
    sort : ?{ #oldest; #newest; #mostLikes; #random; #hotness };
    prioritizeFollowedUsers : ?Bool;
  };

  public type InterestsPref = {
    tags : [Text];
  };

  public type MutedWordTarget = { #content; #tag };

  public type MutedWord = {
    id : ?Text;
    value : Text;
    targets : [MutedWordTarget];
    actorTarget : ?{ #all; #excludeFollowing };
    expiresAt : ?Time.Time;
  };

  public type MutedWordsPref = {
    items : [MutedWord];
  };

  public type HiddenPostsPref = {
    items : [AtUri.AtUri];
  };

  public type LabelerPrefItem = {
    did : DID.DID;
  };

  public type LabelersPref = {
    labelers : [LabelerPrefItem];
  };

  public type BskyAppProgressGuide = {
    guide : Text;
  };

  public type Nux = {
    id : Text;
    completed : Bool;
    data : ?Text;
    expiresAt : ?Time.Time;
  };

  public type BskyAppStatePref = {
    activeProgressGuide : ?BskyAppProgressGuide;
    queuedNudges : ?[Text];
    nuxs : ?[Nux];
  };

  public type VerificationPrefs = {
    hideBadges : ?Bool;
  };

  public type PostInteractionSettingsPref = {
    threadgateAllowRules : ?[Text]; // Union refs - simplified as Text for now
    postgateEmbeddingRules : ?[Text]; // Union refs - simplified as Text for now
  };

  // Union type for all preference types
  public type PreferenceItem = {
    #adultContentPref : AdultContentPref;
    #contentLabelPref : ContentLabelPref;
    #savedFeedsPref : SavedFeedsPref;
    #savedFeedsPrefV2 : SavedFeedsPrefV2;
    #personalDetailsPref : PersonalDetailsPref;
    #feedViewPref : FeedViewPref;
    #threadViewPref : ThreadViewPref;
    #interestsPref : InterestsPref;
    #mutedWordsPref : MutedWordsPref;
    #hiddenPostsPref : HiddenPostsPref;
    #bskyAppStatePref : BskyAppStatePref;
    #labelersPref : LabelersPref;
    #postInteractionSettingsPref : PostInteractionSettingsPref;
    #verificationPrefs : VerificationPrefs;
  };

  public type Preferences = [PreferenceItem];

  public type FeedType = {
    #feed;
    #list;
    #timeline;
  };

  private func feedTypeToText(type_ : FeedType) : Text {
    switch (type_) {
      case (#feed) "feed";
      case (#list) "list";
      case (#timeline) "timeline";
    };
  };

  private func visibilityToText(visibility : ContentVisibility) : Text {
    switch (visibility) {
      case (#ignore_) "ignore";
      case (#show) "show";
      case (#warn) "warn";
      case (#hide) "hide";
    };
  };

  private func textToFeedType(text : Text) : ?FeedType {
    switch (text) {
      case ("feed") ?#feed;
      case ("list") ?#list;
      case ("timeline") ?#timeline;
      case (_) null;
    };
  };

  private func textToVisibility(text : Text) : ?ContentVisibility {
    switch (text) {
      case ("ignore") ?#ignore_;
      case ("show") ?#show;
      case ("warn") ?#warn;
      case ("hide") ?#hide;
      case (_) null;
    };
  };

  // Helper functions for converting preferences to JSON
  public func preferencesToJson(preferences : Preferences) : Json.Json {
    let prefsJson = Array.map<PreferenceItem, Json.Json>(
      preferences,
      func(pref) {
        switch (pref) {
          case (#adultContentPref(p)) {
            #object_([
              ("$type", #string("app.bsky.actor.defs#adultContentPref")),
              ("enabled", #bool(p.enabled)),
            ]);
          };
          case (#contentLabelPref(p)) {
            let fields = DynamicArray.DynamicArray<(Text, Json.Json)>(4);
            fields.add(("$type", #string("app.bsky.actor.defs#contentLabelPref")));
            fields.add(("label", #string(p.label_)));
            fields.add(("visibility", #string(visibilityToText(p.visibility))));
            switch (p.labelerDid) {
              case (?did) fields.add(("labelerDid", #string(DID.toText(did))));
              case (null) ();
            };
            #object_(DynamicArray.toArray(fields));
          };
          case (#savedFeedsPref(p)) {
            let fields = DynamicArray.DynamicArray<(Text, Json.Json)>(4);
            fields.add(("$type", #string("app.bsky.actor.defs#savedFeedsPref")));
            fields.add(("pinned", #array(Array.map<AtUri.AtUri, Json.Json>(p.pinned, func(uri) { #string(AtUri.toText(uri)) }))));
            fields.add(("saved", #array(Array.map<AtUri.AtUri, Json.Json>(p.saved, func(uri) { #string(AtUri.toText(uri)) }))));
            switch (p.timelineIndex) {
              case (?index) fields.add(("timelineIndex", #number(#int(index))));
              case (null) ();
            };
            #object_(DynamicArray.toArray(fields));
          };
          case (#savedFeedsPrefV2(p)) {
            let itemsJson = Array.map<SavedFeed, Json.Json>(
              p.items,
              func(feed) {
                #object_([
                  ("id", #string(feed.id)),
                  ("type", #string(feedTypeToText(feed.type_))),
                  ("value", #string(feed.value)),
                  ("pinned", #bool(feed.pinned)),
                ]);
              },
            );
            #object_([
              ("$type", #string("app.bsky.actor.defs#savedFeedsPrefV2")),
              ("items", #array(itemsJson)),
            ]);
          };
          case (#personalDetailsPref(p)) {
            let fields = DynamicArray.DynamicArray<(Text, Json.Json)>(2);
            fields.add(("$type", #string("app.bsky.actor.defs#personalDetailsPref")));
            switch (p.birthDate) {
              case (?date) fields.add(("birthDate", #string(date)));
              case (null) ();
            };
            #object_(DynamicArray.toArray(fields));
          };
          case (_) {
            // Simplified handling for other preference types
            #object_([("$type", #string("app.bsky.actor.defs#unknownPref"))]);
          };
        };
      },
    );
    #array(prefsJson);
  };

  private func parseAdultContentPref(prefJson : Json.Json) : Result.Result<PreferenceItem, Text> {
    let enabled = switch (Json.getAsBool(prefJson, "enabled")) {
      case (#ok(e)) e;
      case (#err(_)) return #err("Invalid or missing 'enabled' field in adultContentPref");
    };
    #ok(#adultContentPref({ enabled = enabled }));
  };

  private func parseContentLabelPref(prefJson : Json.Json) : Result.Result<PreferenceItem, Text> {
    let label_ = switch (Json.getAsText(prefJson, "label")) {
      case (#ok(l)) l;
      case (#err(_)) return #err("Invalid or missing 'label' field in contentLabelPref");
    };
    let visibilityText = switch (Json.getAsText(prefJson, "visibility")) {
      case (#ok(v)) v;
      case (#err(_)) return #err("Invalid or missing 'visibility' field in contentLabelPref");
    };
    let visibility = switch (textToVisibility(visibilityText)) {
      case (?v) v;
      case (null) return #err("Invalid visibility value: " # visibilityText);
    };
    let labelerDid : ?DID.DID = switch (Json.getAsText(prefJson, "labelerDid")) {
      case (#ok(did)) switch (DID.fromText(did)) {
        case (#ok(d)) ?d;
        case (#err(_)) return #err("Invalid labelerDid format: " # did);
      };
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid labelerDid field type in contentLabelPref");
    };
    #ok(#contentLabelPref({ labelerDid = labelerDid; label_ = label_; visibility = visibility }));
  };

  private func parseSavedFeedsPref(prefJson : Json.Json) : Result.Result<PreferenceItem, Text> {
    let pinnedArray = switch (Json.getAsArray(prefJson, "pinned")) {
      case (#ok(arr)) arr;
      case (#err(_)) return #err("Invalid or missing 'pinned' array in savedFeedsPref");
    };
    let savedArray = switch (Json.getAsArray(prefJson, "saved")) {
      case (#ok(arr)) arr;
      case (#err(_)) return #err("Invalid or missing 'saved' array in savedFeedsPref");
    };

    let pinnedUris = DynamicArray.DynamicArray<AtUri.AtUri>(pinnedArray.size());
    for (item in pinnedArray.vals()) {
      switch (Json.getAsText(item, "")) {
        case (#ok(uri)) {
          switch (AtUri.fromText(uri)) {
            case (?parsedUri) pinnedUris.add(parsedUri);
            case (null) return #err("Invalid URI format in pinned array: " # uri);
          };
        };
        case (#err(_)) return #err("Invalid item in pinned array");
      };
    };

    let savedUris = DynamicArray.DynamicArray<AtUri.AtUri>(savedArray.size());
    for (item in savedArray.vals()) {
      switch (Json.getAsText(item, "")) {
        case (#ok(uri)) {
          switch (AtUri.fromText(uri)) {
            case (?parsedUri) savedUris.add(parsedUri);
            case (null) return #err("Invalid URI format in saved array: " # uri);
          };
        };
        case (#err(_)) return #err("Invalid item in saved array");
      };
    };

    let timelineIndex = switch (Json.getAsInt(prefJson, "timelineIndex")) {
      case (#ok(idx)) ?Int.abs(idx);
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid timelineIndex field type in savedFeedsPref");
    };

    #ok(#savedFeedsPref({ pinned = DynamicArray.toArray(pinnedUris); saved = DynamicArray.toArray(savedUris); timelineIndex = timelineIndex }));
  };

  private func parseSavedFeedsPrefV2(prefJson : Json.Json) : Result.Result<PreferenceItem, Text> {
    let itemsArray = switch (Json.getAsArray(prefJson, "items")) {
      case (#ok(arr)) arr;
      case (#err(_)) return #err("Invalid or missing 'items' array in savedFeedsPrefV2");
    };

    let items = DynamicArray.DynamicArray<SavedFeed>(itemsArray.size());
    for (itemJson in itemsArray.vals()) {
      let id = switch (Json.getAsText(itemJson, "id")) {
        case (#ok(i)) i;
        case (#err(_)) return #err("Invalid or missing 'id' field in savedFeed item");
      };
      let typeText = switch (Json.getAsText(itemJson, "type")) {
        case (#ok(t)) t;
        case (#err(_)) return #err("Invalid or missing 'type' field in savedFeed item");
      };
      let type_ = switch (textToFeedType(typeText)) {
        case (?t) t;
        case (null) return #err("Invalid feed type value: " # typeText);
      };
      let value = switch (Json.getAsText(itemJson, "value")) {
        case (#ok(v)) v;
        case (#err(_)) return #err("Invalid or missing 'value' field in savedFeed item");
      };
      let pinned = switch (Json.getAsBool(itemJson, "pinned")) {
        case (#ok(p)) p;
        case (#err(_)) return #err("Invalid or missing 'pinned' field in savedFeed item");
      };
      items.add({
        id = id;
        type_ = type_;
        value = value;
        pinned = pinned;
      });
    };

    #ok(#savedFeedsPrefV2({ items = DynamicArray.toArray(items) }));
  };

  private func parsePersonalDetailsPref(prefJson : Json.Json) : Result.Result<PreferenceItem, Text> {
    let birthDate = switch (Json.getAsText(prefJson, "birthDate")) {
      case (#ok(date)) ?date;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid birthDate field type in personalDetailsPref");
    };
    #ok(#personalDetailsPref({ birthDate = birthDate }));
  };

  public func preferencesFromJson(json : Json.Json) : Result.Result<Preferences, Text> {
    let prefsArray = switch (Json.getAsArray(json, "")) {
      case (#ok(arr)) arr;
      case (#err(#pathNotFound)) return #err("Invalid preferences, expected array");
      case (#err(#typeMismatch)) return #err("Invalid preferences, expected array");
    };

    let preferences = DynamicArray.DynamicArray<PreferenceItem>(prefsArray.size());

    label f for (prefJson in prefsArray.vals()) {
      let typeStr = switch (Json.getAsText(prefJson, "$type")) {
        case (#ok(t)) t;
        case (#err(_)) return #err("Invalid or missing '$type' field in preference item");
      };

      let result = switch (typeStr) {
        case ("app.bsky.actor.defs#adultContentPref") parseAdultContentPref(prefJson);
        case ("app.bsky.actor.defs#contentLabelPref") parseContentLabelPref(prefJson);
        case ("app.bsky.actor.defs#savedFeedsPref") parseSavedFeedsPref(prefJson);
        case ("app.bsky.actor.defs#savedFeedsPrefV2") parseSavedFeedsPrefV2(prefJson);
        case ("app.bsky.actor.defs#personalDetailsPref") parsePersonalDetailsPref(prefJson);
        case (_) {
          // Skip unknown preference types by continuing to next iteration
          continue f;
        };
      };

      switch (result) {
        case (#ok(pref)) preferences.add(pref);
        case (#err(e)) return #err(e);
      };
    };

    #ok(DynamicArray.toArray(preferences));
  };

};
