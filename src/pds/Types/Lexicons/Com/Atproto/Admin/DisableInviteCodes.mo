import Json "mo:json@1";
import Result "mo:core@1/Result";
import Array "mo:base/Array";

module {

  /// Request type for com.atproto.admin.disableInviteCodes
  /// Disable some set of codes and/or all codes associated with a set of users.
  public type Request = {
    /// Optional array of specific invite codes to disable
    codes : ?[Text];

    /// Optional array of account DIDs whose invite codes should be disabled
    accounts : ?[Text];
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let codes = switch (Json.getAsArray(json, "codes")) {
      case (#ok(arr)) {
        let codeStrings = Array.mapFilter<Json.Json, Text>(
          arr,
          func(item) {
            switch (item) {
              case (#string(s)) ?s;
              case (_) null;
            };
          },
        );
        if (codeStrings.size() == arr.size()) ?codeStrings else return #err("Invalid codes array, expected string items");
      };
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid codes field, expected array");
    };

    let accounts = switch (Json.getAsArray(json, "accounts")) {
      case (#ok(arr)) {
        let accountStrings = Array.mapFilter<Json.Json, Text>(
          arr,
          func(item) {
            switch (item) {
              case (#string(s)) ?s;
              case (_) null;
            };
          },
        );
        if (accountStrings.size() == arr.size()) ?accountStrings else return #err("Invalid accounts array, expected string items");
      };
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid accounts field, expected array");
    };

    #ok({
      codes = codes;
      accounts = accounts;
    });
  };

};
