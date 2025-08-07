import Json "mo:json";
import Result "mo:core/Result";

module {

  /// Request type for com.atproto.admin.sendEmail
  /// Send email to a user's account email address.
  public type Request = {
    /// DID of the email recipient
    recipientDid : Text; // DID string

    /// Email content/body
    content : Text;

    /// Optional email subject
    subject : ?Text;

    /// DID of the email sender
    senderDid : Text; // DID string

    /// Optional additional comment for moderators/reviewers
    comment : ?Text;
  };

  /// Response type for com.atproto.admin.sendEmail
  public type Response = {
    /// Whether the email was sent successfully
    sent : Bool;
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let recipientDid = switch (Json.getAsText(json, "recipientDid")) {
      case (#ok(did)) did;
      case (#err(#pathNotFound)) return #err("Missing required field: recipientDid");
      case (#err(#typeMismatch)) return #err("Invalid recipientDid field, expected string");
    };

    let content = switch (Json.getAsText(json, "content")) {
      case (#ok(content)) content;
      case (#err(#pathNotFound)) return #err("Missing required field: content");
      case (#err(#typeMismatch)) return #err("Invalid content field, expected string");
    };

    let subject = switch (Json.getAsText(json, "subject")) {
      case (#ok(subject)) ?subject;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid subject field, expected string");
    };

    let senderDid = switch (Json.getAsText(json, "senderDid")) {
      case (#ok(did)) did;
      case (#err(#pathNotFound)) return #err("Missing required field: senderDid");
      case (#err(#typeMismatch)) return #err("Invalid senderDid field, expected string");
    };

    let comment = switch (Json.getAsText(json, "comment")) {
      case (#ok(comment)) ?comment;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid comment field, expected string");
    };

    #ok({
      recipientDid = recipientDid;
      content = content;
      subject = subject;
      senderDid = senderDid;
      comment = comment;
    });
  };

  public func toJson(response : Response) : Json.Json {
    #object_([
      ("sent", #bool(response.sent)),
    ]);
  };

};
