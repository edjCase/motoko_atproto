import DagCbor "mo:dag-cbor";
import Json "mo:json";
import Array "mo:base/Array";
import JsonDagCborMapper "../../../../../JsonDagCborMapper";
import ServerDefs "../Server/Defs";

module {

  /// Status attribute indicating if something has been applied
  public type StatusAttr = {
    /// Whether the status has been applied
    applied : Bool;

    /// Optional reference
    ref : ?Text;
  };

  /// Account view with comprehensive account information
  public type AccountView = {
    /// Account DID
    did : Text; // DID string

    /// Account handle
    handle : Text; // Handle string

    /// Optional email address
    email : ?Text;

    /// Related records (type unknown in schema)
    relatedRecords : ?[DagCbor.Value];

    /// When the account was indexed
    indexedAt : Text; // Datetime string

    /// Invite code that was used to create this account
    invitedBy : ?ServerDefs.InviteCode;

    /// Invite codes created by this account
    invites : ?[ServerDefs.InviteCode];

    /// Whether invites are disabled for this account
    invitesDisabled : ?Bool;

    /// When email was confirmed
    emailConfirmedAt : ?Text; // Datetime string

    /// Note associated with the invite
    inviteNote : ?Text;

    /// When the account was deactivated
    deactivatedAt : ?Text; // Datetime string

    /// Threat signatures associated with this account
    threatSignatures : ?[ThreatSignature];
  };

  /// Repository reference containing just a DID
  public type RepoRef = {
    /// Repository DID
    did : Text; // DID string
  };

  /// Repository blob reference with DID and CID
  public type RepoBlobRef = {
    /// Repository DID
    did : Text; // DID string

    /// Content identifier
    cid : Text; // CID string

    /// Optional record URI
    recordUri : ?Text; // AT-URI string
  };

  /// Threat signature for security analysis
  public type ThreatSignature = {
    /// Property name
    property : Text;

    /// Property value
    value : Text;
  };

  public func statusAttrToJson(statusAttr : StatusAttr) : Json.Json {
    let refJson = switch (statusAttr.ref) {
      case (?ref) #string(ref);
      case (null) #null_;
    };

    #object_([
      ("applied", #bool(statusAttr.applied)),
      ("ref", refJson),
    ]);
  };

  public func accountViewToJson(accountView : AccountView) : Json.Json {

    let fields = DynamicArray.DynamicArray<(Text, Json.Json)>(15);

    fields.add(("did", #string(accountView.did)));
    fields.add(("handle", #string(accountView.handle)));
    fields.add(("indexedAt", #string(accountView.indexedAt)));

    switch (accountView.email) {
      case (?email) fields.add(("email", #string(email)));
      case (null) ();
    };

    switch (accountView.relatedRecords) {
      case (?records) {
        let recordsArray = records |> Array.map<DagCbor.Value, Json.Json>(_, JsonDagCborMapper.fromDagCbor);
        fields.add(("relatedRecords", #array(recordsArray)));
      };
      case (null) ();
    };

    switch (accountView.invitedBy) {
      case (?inviteCode) fields.add(("invitedBy", ServerDefs.inviteCodeToJson(inviteCode)));
      case (null) ();
    };

    switch (accountView.invites) {
      case (?invites) {
        let invitesArray = invites |> Array.map<ServerDefs.InviteCode, Json.Json>(_, ServerDefs.inviteCodeToJson);
        fields.add(("invites", #array(invitesArray)));
      };
      case (null) ();
    };

    switch (accountView.invitesDisabled) {
      case (?disabled) fields.add(("invitesDisabled", #bool(disabled)));
      case (null) ();
    };

    switch (accountView.emailConfirmedAt) {
      case (?confirmedAt) fields.add(("emailConfirmedAt", #string(confirmedAt)));
      case (null) ();
    };

    switch (accountView.inviteNote) {
      case (?note) fields.add(("inviteNote", #string(note)));
      case (null) ();
    };

    switch (accountView.deactivatedAt) {
      case (?deactivatedAt) fields.add(("deactivatedAt", #string(deactivatedAt)));
      case (null) ();
    };

    switch (accountView.threatSignatures) {
      case (?signatures) {
        let signaturesArray = signatures |> Array.map<ThreatSignature, Json.Json>(_, threatSignatureToJson);
        fields.add(("threatSignatures", #array(signaturesArray)));
      };
      case (null) ();
    };

    #object_(DynamicArray.toArray(fields));
  };

  public func repoRefToJson(repoRef : RepoRef) : Json.Json {
    #object_([
      ("did", #string(repoRef.did)),
    ]);
  };

  public func repoBlobRefToJson(repoBlobRef : RepoBlobRef) : Json.Json {
    let recordUriJson = switch (repoBlobRef.recordUri) {
      case (?uri) #string(uri);
      case (null) #null_;
    };

    #object_([
      ("did", #string(repoBlobRef.did)),
      ("cid", #string(repoBlobRef.cid)),
      ("recordUri", recordUriJson),
    ]);
  };

  public func threatSignatureToJson(threatSignature : ThreatSignature) : Json.Json {
    #object_([
      ("property", #string(threatSignature.property)),
      ("value", #string(threatSignature.value)),
    ]);
  };

};
