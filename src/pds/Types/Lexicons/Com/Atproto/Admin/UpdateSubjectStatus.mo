import Json "mo:json";
import Result "mo:core/Result";
import AdminDefs "./Defs";
import StrongRef "../../../../StrongRef";
import CID "mo:cid";
import AtUri "../../../../AtUri";

module {

  /// Subject union type for UpdateSubjectStatus
  public type Subject = {
    #repoRef : AdminDefs.RepoRef;
    #strongRef : StrongRef.StrongRef;
    #repoBlobRef : AdminDefs.RepoBlobRef;
  };

  /// Request type for com.atproto.admin.updateSubjectStatus
  /// Update the service-specific admin status of a subject (account, record, or blob).
  public type Request = {
    /// Subject to update status for
    subject : Subject;

    /// Optional takedown status to set
    takedown : ?AdminDefs.StatusAttr;

    /// Optional deactivated status to set
    deactivated : ?AdminDefs.StatusAttr;
  };

  /// Response type for com.atproto.admin.updateSubjectStatus
  public type Response = {
    /// Subject that was updated
    subject : Subject;

    /// Optional takedown status
    takedown : ?AdminDefs.StatusAttr;
  };

  public func subjectFromJson(json : Json.Json) : Result.Result<Subject, Text> {
    // Try to parse as repoRef first (has only "did" field)
    switch (Json.getAsText(json, "did")) {
      case (#ok(did)) {
        // Check if it has additional fields that would make it repoBlobRef
        switch (Json.getAsText(json, "cid")) {
          case (#ok(cid)) {
            let recordUri = switch (Json.getAsText(json, "recordUri")) {
              case (#ok(uri)) ?uri;
              case (_) null;
            };
            return #ok(#repoBlobRef({ did = did; cid = cid; recordUri = recordUri }));
          };
          case (_) {
            return #ok(#repoRef({ did = did }));
          };
        };
      };
      case (_) {
        // Try to parse as strongRef (has "uri" and "cid" fields)
        let uri = switch (Json.getAsText(json, "uri")) {
          case (#ok(uri)) uri;
          case (_) return #err("Subject must have either 'did' or 'uri' field");
        };

        let atUri = switch (AtUri.fromText(uri)) {
          case (?atUri) atUri;
          case (null) return #err("Invalid uri, not valid AT-URI format");
        };

        let cidText = switch (Json.getAsText(json, "cid")) {
          case (#ok(cid)) cid;
          case (_) return #err("StrongRef subject must have 'cid' field");
        };

        let cid = switch (CID.fromText(cidText)) {
          case (#ok(cid)) cid;
          case (#err(e)) return #err("Invalid CID: " # e);
        };

        return #ok(#strongRef({ uri = atUri; cid = cid }));
      };
    };
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let subjectJson = switch (Json.get(json, "subject")) {
      case (?subjectJson) subjectJson;
      case (null) return #err("Missing required field: subject");
    };

    let subject = switch (subjectFromJson(subjectJson)) {
      case (#ok(subject)) subject;
      case (#err(e)) return #err("Invalid subject: " # e);
    };

    let takedown = switch (Json.get(json, "takedown")) {
      case (?takedownJson) {
        let applied = switch (Json.getAsBool(takedownJson, "applied")) {
          case (#ok(applied)) applied;
          case (_) return #err("Invalid takedown.applied field, expected boolean");
        };
        let ref = switch (Json.getAsText(takedownJson, "ref")) {
          case (#ok(ref)) ?ref;
          case (#err(#pathNotFound)) null;
          case (_) return #err("Invalid takedown.ref field, expected string");
        };
        ?{ applied = applied; ref = ref };
      };
      case (null) null;
    };

    let deactivated = switch (Json.get(json, "deactivated")) {
      case (?deactivatedJson) {
        let applied = switch (Json.getAsBool(deactivatedJson, "applied")) {
          case (#ok(applied)) applied;
          case (_) return #err("Invalid deactivated.applied field, expected boolean");
        };
        let ref = switch (Json.getAsText(deactivatedJson, "ref")) {
          case (#ok(ref)) ?ref;
          case (#err(#pathNotFound)) null;
          case (_) return #err("Invalid deactivated.ref field, expected string");
        };
        ?{ applied = applied; ref = ref };
      };
      case (null) null;
    };

    #ok({
      subject = subject;
      takedown = takedown;
      deactivated = deactivated;
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

    #object_([
      ("subject", subjectToJson(response.subject)),
      ("takedown", takedownJson),
    ]);
  };

};
