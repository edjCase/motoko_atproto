import Json "mo:json";
import Result "mo:core/Result";
import AdminDefs "./Defs";
import StrongRef "../../../../StrongRef";
import CID "mo:cid";
import AtUri "../../../../AtUri";

module {

  /// Subject union type for GetSubjectStatus
  public type Subject = {
    #repoRef : AdminDefs.RepoRef;
    #strongRef : StrongRef.StrongRef;
    #repoBlobRef : AdminDefs.RepoBlobRef;
  };

  /// Request type for com.atproto.admin.getSubjectStatus
  /// Get the service-specific admin status of a subject (account, record, or blob).
  public type Request = {
    /// Optional DID for account subject
    did : ?Text; // DID string

    /// Optional AT-URI for record subject
    uri : ?Text; // AT-URI string

    /// Optional CID for blob subject
    blob : ?Text; // CID string
  };

  /// Response type for com.atproto.admin.getSubjectStatus
  public type Response = {
    /// Subject being queried
    subject : Subject;

    /// Optional takedown status
    takedown : ?AdminDefs.StatusAttr;

    /// Optional deactivated status
    deactivated : ?AdminDefs.StatusAttr;
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let did = switch (Json.getAsText(json, "did")) {
      case (#ok(did)) ?did;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid did field, expected string");
    };

    let uri = switch (Json.getAsText(json, "uri")) {
      case (#ok(uri)) ?uri;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid uri field, expected string");
    };

    let blob = switch (Json.getAsText(json, "blob")) {
      case (#ok(blob)) ?blob;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid blob field, expected string");
    };

    #ok({
      did = did;
      uri = uri;
      blob = blob;
    });
  };

  public func subjectToJson(subject : Subject) : Json.Json {
    switch (subject) {
      case (#repoRef(repoRef)) AdminDefs.repoRefToJson(repoRef);
      case (#strongRef(strongRef)) {
        #object_([
          ("uri", #string(AtUri.toText(strongRef.uri))),
          ("cid", #string(CID.toText(strongRef.cid))),
        ]);
      };
      case (#repoBlobRef(repoBlobRef)) AdminDefs.repoBlobRefToJson(repoBlobRef);
    };
  };

  public func toJson(response : Response) : Json.Json {
    let takedownJson = switch (response.takedown) {
      case (?takedown) AdminDefs.statusAttrToJson(takedown);
      case (null) #null_;
    };

    let deactivatedJson = switch (response.deactivated) {
      case (?deactivated) AdminDefs.statusAttrToJson(deactivated);
      case (null) #null_;
    };

    #object_([
      ("subject", subjectToJson(response.subject)),
      ("takedown", takedownJson),
      ("deactivated", deactivatedJson),
    ]);
  };

};
