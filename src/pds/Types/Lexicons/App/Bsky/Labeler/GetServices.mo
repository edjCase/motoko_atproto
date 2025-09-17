import Json "mo:json@1";
import Result "mo:core@1/Result";
import Array "mo:core@1/Array";
import Nat "mo:core@1/Nat";
import DID "mo:did@3";
import CID "mo:cid@1";
import AtUri "../../../../AtUri";
import DateTime "mo:datetime@1/DateTime";
import DynamicArray "mo:xtended-collections@0/DynamicArray";
import Iter "mo:core@1/Iter";

module {

  /// Request type for app.bsky.labeler.getServices
  /// Get information about a list of labeler services.
  public type Request = {
    /// Array of DIDs for labeler services to fetch
    dids : [Text]; // Array of DID strings

    /// Whether to return detailed views
    detailed : ?Bool;
  };

  /// Label severity levels
  public type LabelSeverity = {
    #inform;
    #alert;
    #none;
  };

  /// Label blur settings
  public type LabelBlurs = {
    #content;
    #media;
    #none;
  };

  /// Label default setting
  public type LabelDefaultSetting = {
    #ignore_;
    #warn;
    #hide;
  };

  /// Localized string
  public type LocalizedString = {
    lang : Text; // Language code
    name : Text;
    description : Text;
  };

  /// Label value definition
  public type LabelValueDefinition = {
    identifier : Text;
    severity : LabelSeverity;
    blurs : LabelBlurs;
    defaultSetting : LabelDefaultSetting;
    adultOnly : ?Bool;
    locales : ?[LocalizedString];
  };

  /// Labeler policies
  public type LabelerPolicies = {
    labelValues : [Text]; // Known values - simplified as Text array
    labelValueDefinitions : ?[LabelValueDefinition];
  };

  /// Labeler labels
  public type LabelerLabels = {
    version : ?Nat;
    labels : [Text]; // Simplified as Text array
  };

  /// Labeler view (basic)
  public type LabelerView = {
    uri : AtUri.AtUri;
    cid : CID.CID;
    creator : DID.DID;
    indexedAt : Nat; // Epoch Nanoseconds

    // Labeler record fields
    policies : LabelerPolicies;
    labels : ?LabelerLabels;
    createdAt : Nat; // Epoch Nanoseconds
  };

  /// Labeler view detailed (extends basic view)
  public type LabelerViewDetailed = LabelerView and {
    // Additional detailed fields would go here
  };

  /// Union type for labeler views
  public type LabelerViewUnion = {
    #labelerView : LabelerView;
    #labelerViewDetailed : LabelerViewDetailed;
  };

  /// Response type for app.bsky.labeler.getServices
  public type Response = {
    views : [LabelerViewUnion];
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let dids = switch (Json.getAsArray(json, "dids")) {
      case (#ok(didsArray)) {
        let dynamicArray = DynamicArray.DynamicArray<Text>(didsArray.size());
        for ((idx, didJson) in Iter.enumerate(didsArray.vals())) {
          let #string(did) = didJson else return #err("Invalid DID at index " # Nat.toText(idx) # ", expected string");
          dynamicArray.add(did);
        };
        DynamicArray.toArray(dynamicArray);
      };
      case (#err(#pathNotFound)) return #err("Missing required field: dids");
      case (#err(#typeMismatch)) return #err("Invalid dids field, expected array");
    };

    let detailed = switch (Json.getAsBool(json, "detailed")) {
      case (#ok(detailed)) ?detailed;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid detailed field, expected boolean");
    };

    #ok({
      dids = dids;
      detailed = detailed;
    });
  };

  // Helper functions for converting variants to text
  private func severityToText(severity : LabelSeverity) : Text {
    switch (severity) {
      case (#inform) "inform";
      case (#alert) "alert";
      case (#none) "none";
    };
  };

  private func blursToText(blurs : LabelBlurs) : Text {
    switch (blurs) {
      case (#content) "content";
      case (#media) "media";
      case (#none) "none";
    };
  };

  private func defaultSettingToText(setting : LabelDefaultSetting) : Text {
    switch (setting) {
      case (#ignore_) "ignore";
      case (#warn) "warn";
      case (#hide) "hide";
    };
  };

  private func labelerViewToJson(view : LabelerView) : Json.Json {
    let fields = DynamicArray.DynamicArray<(Text, Json.Json)>(8);

    fields.add(("$type", #string("app.bsky.labeler.defs#labelerView")));
    fields.add(("uri", #string(AtUri.toText(view.uri))));
    fields.add(("cid", #string(CID.toText(view.cid))));
    fields.add(("creator", #string(DID.toText(view.creator))));
    fields.add(("indexedAt", #string(DateTime.DateTime(view.indexedAt).toText())));
    fields.add(("createdAt", #string(DateTime.DateTime(view.createdAt).toText())));

    // Add policies
    let policiesFields = DynamicArray.DynamicArray<(Text, Json.Json)>(2);
    policiesFields.add(("labelValues", #array(Array.map<Text, Json.Json>(view.policies.labelValues, func(v) { #string(v) }))));
    switch (view.policies.labelValueDefinitions) {
      case (?defs) {
        let defsJson = Array.map<LabelValueDefinition, Json.Json>(
          defs,
          func(def) {
            #object_([
              ("identifier", #string(def.identifier)),
              ("severity", #string(severityToText(def.severity))),
              ("blurs", #string(blursToText(def.blurs))),
              ("defaultSetting", #string(defaultSettingToText(def.defaultSetting))),
            ]);
          },
        );
        policiesFields.add(("labelValueDefinitions", #array(defsJson)));
      };
      case (null) ();
    };
    fields.add(("policies", #object_(DynamicArray.toArray(policiesFields))));

    switch (view.labels) {
      case (?labels) {
        let labelsFields = DynamicArray.DynamicArray<(Text, Json.Json)>(2);
        switch (labels.version) {
          case (?version) labelsFields.add(("version", #number(#int(version))));
          case (null) ();
        };
        labelsFields.add(("labels", #array(Array.map<Text, Json.Json>(labels.labels, func(l) { #string(l) }))));
        fields.add(("labels", #object_(DynamicArray.toArray(labelsFields))));
      };
      case (null) ();
    };

    #object_(DynamicArray.toArray(fields));
  };

  private func labelerViewDetailedToJson(view : LabelerViewDetailed) : Json.Json {
    let fields = DynamicArray.DynamicArray<(Text, Json.Json)>(8);

    fields.add(("$type", #string("app.bsky.labeler.defs#labelerViewDetailed")));
    fields.add(("uri", #string(AtUri.toText(view.uri))));
    fields.add(("cid", #string(CID.toText(view.cid))));
    fields.add(("creator", #string(DID.toText(view.creator))));
    fields.add(("indexedAt", #string(DateTime.DateTime(view.indexedAt).toText())));
    fields.add(("createdAt", #string(DateTime.DateTime(view.createdAt).toText())));

    // Add policies (same as basic view)
    let policiesFields = DynamicArray.DynamicArray<(Text, Json.Json)>(2);
    policiesFields.add(("labelValues", #array(Array.map<Text, Json.Json>(view.policies.labelValues, func(v) { #string(v) }))));
    switch (view.policies.labelValueDefinitions) {
      case (?defs) {
        let defsJson = Array.map<LabelValueDefinition, Json.Json>(
          defs,
          func(def) {
            #object_([
              ("identifier", #string(def.identifier)),
              ("severity", #string(severityToText(def.severity))),
              ("blurs", #string(blursToText(def.blurs))),
              ("defaultSetting", #string(defaultSettingToText(def.defaultSetting))),
            ]);
          },
        );
        policiesFields.add(("labelValueDefinitions", #array(defsJson)));
      };
      case (null) ();
    };
    fields.add(("policies", #object_(DynamicArray.toArray(policiesFields))));

    switch (view.labels) {
      case (?labels) {
        let labelsFields = DynamicArray.DynamicArray<(Text, Json.Json)>(2);
        switch (labels.version) {
          case (?version) labelsFields.add(("version", #number(#int(version))));
          case (null) ();
        };
        labelsFields.add(("labels", #array(Array.map<Text, Json.Json>(labels.labels, func(l) { #string(l) }))));
        fields.add(("labels", #object_(DynamicArray.toArray(labelsFields))));
      };
      case (null) ();
    };

    #object_(DynamicArray.toArray(fields));
  };

  public func toJson(response : Response) : Json.Json {
    let viewsJson = Array.map<LabelerViewUnion, Json.Json>(
      response.views,
      func(view) {
        switch (view) {
          case (#labelerView(v)) labelerViewToJson(v);
          case (#labelerViewDetailed(v)) labelerViewDetailedToJson(v);
        };
      },
    );

    #object_([("views", #array(viewsJson))]);
  };

};
