import Json "mo:json";
import Result "mo:new-base/Result";
import Array "mo:base/Array";
import ServerDefs "../Server/Defs";

module {

  /// Request type for com.atproto.admin.getInviteCodes
  /// Get an admin view of invite codes.
  public type Request = {
    /// Sort order for invite codes
    sort : ?Text; // "recent" or "usage", default "recent"

    /// Maximum number of codes to return
    limit : ?Int; // 1-500, default 100

    /// Cursor for pagination
    cursor : ?Text;
  };

  /// Response type for com.atproto.admin.getInviteCodes
  public type Response = {
    /// Optional cursor for pagination
    cursor : ?Text;

    /// Array of invite codes
    codes : [ServerDefs.InviteCode];
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let sort = switch (Json.getAsText(json, "sort")) {
      case (#ok(sort)) ?sort;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid sort field, expected string");
    };

    let limit = switch (Json.getAsInt(json, "limit")) {
      case (#ok(limit)) ?limit;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid limit field, expected integer");
    };

    let cursor = switch (Json.getAsText(json, "cursor")) {
      case (#ok(cursor)) ?cursor;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid cursor field, expected string");
    };

    #ok({
      sort = sort;
      limit = limit;
      cursor = cursor;
    });
  };

  public func toJson(response : Response) : Json.Json {
    let cursorJson = switch (response.cursor) {
      case (?cursor) #string(cursor);
      case (null) #null_;
    };

    let codesJson = response.codes |> Array.map<ServerDefs.InviteCode, Json.Json>(_, ServerDefs.inviteCodeToJson);

    #object_([
      ("cursor", cursorJson),
      ("codes", #array(codesJson)),
    ]);
  };

};
