import Json "mo:json";
import Array "mo:base/Array";
import DID "mo:did";
import AtUri "../../../../AtUri";
import DateTime "mo:datetime/DateTime";
import LabelDefs "../../../Com/Atproto/Label/Defs";
import DynamicArray "mo:xtended-collections/DynamicArray";

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
    avatar : ?AtUri.AtUri; // URI

    /// Creation timestamp
    createdAt : ?Nat; // Epoch Nanoseconds

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
    indexedAt : ?Nat; // Epoch Nanoseconds
  };

  /// Detailed profile view with complete information
  public type ProfileViewDetailed = ProfileView and {
    /// Optional banner image
    banner : ?AtUri.AtUri; // URI

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
    createdAt : Nat; // Epoch Nanoseconds
  };

  /// Status view information
  public type StatusView = {
    status : Text; // Known value: "app.bsky.actor.status#live"
    record : Json.Json; // Unknown type - using Json for flexibility
    embed : ?Text; // Reference to embed - simplified as Text for now
    expiresAt : ?Nat; // Epoch Nanoseconds
    isActive : ?Bool;
  };

  // Helper function to add basic profile fields that are common to all profile types
  private func addBasicProfileFields(fields : DynamicArray.DynamicArray<(Text, Json.Json)>, profile : ProfileViewBasic, typeString : Text) : () {
    let labelsJson = Array.map<LabelDefs.Label, Json.Json>(profile.labels, LabelDefs.labelToJson);

    fields.add(("$type", #string(typeString)));
    fields.add(("did", #string(DID.Plc.toText(profile.did))));
    fields.add(("handle", #string(profile.handle)));
    fields.add(("labels", #array(labelsJson)));

    switch (profile.displayName) {
      case (?displayName) fields.add(("displayName", #string(displayName)));
      case (null) ();
    };

    switch (profile.avatar) {
      case (?avatar) fields.add(("avatar", #string(AtUri.toText(avatar))));
      case (null) ();
    };

    switch (profile.createdAt) {
      case (?createdAt) fields.add(("createdAt", #string(DateTime.DateTime(createdAt).toText())));
      case (null) ();
    };
  };

  // Helper function to add ProfileView fields (includes basic fields + ProfileView-specific fields)
  private func addProfileViewFields(fields : DynamicArray.DynamicArray<(Text, Json.Json)>, profile : ProfileView, typeString : Text) : () {
    // Add basic fields first
    addBasicProfileFields(fields, profile, typeString);

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
    addBasicProfileFields(fields, profile, "app.bsky.actor.defs#profileViewBasic");
    #object_(DynamicArray.toArray(fields));
  };

  public func profileViewToJson(profile : ProfileView) : Json.Json {
    let fields = DynamicArray.DynamicArray<(Text, Json.Json)>(12);
    addProfileViewFields(fields, profile, "app.bsky.actor.defs#profileView");
    #object_(DynamicArray.toArray(fields));
  };
  public func profileViewDetailedToJson(profile : ProfileViewDetailed) : Json.Json {
    let fields = DynamicArray.DynamicArray<(Text, Json.Json)>(15);

    // Add ProfileView fields using helper (includes basic + ProfileView fields)
    addProfileViewFields(fields, profile, "app.bsky.actor.defs#profileViewDetailed");

    // Add ProfileViewDetailed-specific fields
    switch (profile.banner) {
      case (?banner) fields.add(("banner", #string(AtUri.toText(banner))));
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
    expiresAt : ?DateTime.DateTime;
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
    expiresAt : ?DateTime.DateTime;
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

};
