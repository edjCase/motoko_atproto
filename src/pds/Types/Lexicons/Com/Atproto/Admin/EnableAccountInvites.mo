import Json "mo:json";
import Result "mo:new-base/Result";

module {

  /// Request type for com.atproto.admin.enableAccountInvites
  /// Re-enable an account's ability to receive invite codes.
  public type Request = {
    /// DID of the account to enable invites for
    account : Text; // DID string

    /// Optional reason for enabled invites
    note : ?Text;
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let account = switch (Json.getAsText(json, "account")) {
      case (#ok(account)) account;
      case (#err(#pathNotFound)) return #err("Missing required field: account");
      case (#err(#typeMismatch)) return #err("Invalid account field, expected string");
    };

    let note = switch (Json.getAsText(json, "note")) {
      case (#ok(note)) ?note;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid note field, expected string");
    };

    #ok({
      account = account;
      note = note;
    });
  };

};
