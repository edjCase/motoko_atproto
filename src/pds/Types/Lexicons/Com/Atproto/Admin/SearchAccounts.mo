import Json "mo:json";
import Result "mo:new-base/Result";
import Array "mo:base/Array";
import AdminDefs "./Defs";

module {

  /// Request type for com.atproto.admin.searchAccounts
  /// Get list of accounts that matches your search query.
  public type Request = {
    /// Optional email to search for
    email : ?Text;

    /// Optional cursor for pagination
    cursor : ?Text;

    /// Maximum number of accounts to return
    limit : ?Int; // 1-100, default 50
  };

  /// Response type for com.atproto.admin.searchAccounts
  public type Response = {
    /// Optional cursor for pagination
    cursor : ?Text;

    /// Array of matching accounts
    accounts : [AdminDefs.AccountView];
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let email = switch (Json.getAsText(json, "email")) {
      case (#ok(email)) ?email;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid email field, expected string");
    };

    let cursor = switch (Json.getAsText(json, "cursor")) {
      case (#ok(cursor)) ?cursor;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid cursor field, expected string");
    };

    let limit = switch (Json.getAsInt(json, "limit")) {
      case (#ok(limit)) ?limit;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid limit field, expected integer");
    };

    #ok({
      email = email;
      cursor = cursor;
      limit = limit;
    });
  };

  public func toJson(response : Response) : Json.Json {
    let cursorJson = switch (response.cursor) {
      case (?cursor) #string(cursor);
      case (null) #null_;
    };

    let accountsJson = response.accounts |> Array.map<AdminDefs.AccountView, Json.Json>(_, AdminDefs.accountViewToJson);

    #object_([
      ("cursor", cursorJson),
      ("accounts", #array(accountsJson)),
    ]);
  };

};
