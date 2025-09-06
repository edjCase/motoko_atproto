import Json "mo:json@1";
import Result "mo:core@1/Result";
import Array "mo:base/Array";
import AdminDefs "./Defs";

module {

  /// Request type for com.atproto.admin.getAccountInfos
  /// Get details about some accounts.
  public type Request = {
    /// Array of DIDs to get account info for
    dids : [Text]; // Array of DID strings
  };

  /// Response type for com.atproto.admin.getAccountInfos
  public type Response = {
    /// Array of account information
    infos : [AdminDefs.AccountView];
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let dids = switch (Json.getAsArray(json, "dids")) {
      case (#ok(arr)) {
        let didStrings = Array.mapFilter<Json.Json, Text>(
          arr,
          func(item) {
            switch (item) {
              case (#string(s)) ?s;
              case (_) null;
            };
          },
        );
        if (didStrings.size() == arr.size()) didStrings else return #err("Invalid dids array, expected string items");
      };
      case (#err(#pathNotFound)) return #err("Missing required field: dids");
      case (#err(#typeMismatch)) return #err("Invalid dids field, expected array");
    };

    #ok({
      dids = dids;
    });
  };

  public func toJson(response : Response) : Json.Json {
    let infosJson = response.infos |> Array.map<AdminDefs.AccountView, Json.Json>(_, AdminDefs.accountViewToJson);

    #object_([
      ("infos", #array(infosJson)),
    ]);
  };

};
