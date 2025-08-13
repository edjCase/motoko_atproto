import Json "mo:json";
import Array "mo:base/Array";
import Option "mo:core/Option";
import DID "mo:did";
import AtUri "../../../../AtUri";
import DateTime "mo:datetime/DateTime";
import BaseX "mo:base-x-encoder";
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

};
