import Result "mo:core@1/Result";
import Json "mo:json@1";
import Array "mo:core@1/Array";

module {

  public type AccountCodes = {
    account : Text;
    codes : [Text];
  };

  public type Request = {
    codeCount : Int;
    useCount : Int;
    forAccounts : ?[Text]; // DID strings
  };

  public type Response = {
    codes : [AccountCodes];
  };

  public func toJson(response : Response) : Json.Json {
    let codesJson = response.codes |> Array.map<AccountCodes, Json.Json>(
      _,
      func(ac) {
        let codesArray = ac.codes |> Array.map<Text, Json.Json>(_, func(code) = #string(code));
        #object_([
          ("account", #string(ac.account)),
          ("codes", #array(codesArray)),
        ]);
      },
    );

    #object_([
      ("codes", #array(codesJson)),
    ]);
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let codeCount = switch (Json.getAsInt(json, "codeCount")) {
      case (#ok(count)) count;
      case (#err(#pathNotFound)) return #err("Missing required field: codeCount");
      case (#err(#typeMismatch)) return #err("Invalid codeCount field, expected integer");
    };

    let useCount = switch (Json.getAsInt(json, "useCount")) {
      case (#ok(count)) count;
      case (#err(#pathNotFound)) return #err("Missing required field: useCount");
      case (#err(#typeMismatch)) return #err("Invalid useCount field, expected integer");
    };

    let forAccounts = switch (Json.getAsArray(json, "forAccounts")) {
      case (#ok(arr)) {
        let accounts = Array.mapFilter<Json.Json, Text>(
          arr,
          func(item) {
            switch (item) {
              case (#string(s)) ?s;
              case (_) null;
            };
          },
        );
        if (accounts.size() == arr.size()) ?accounts else return #err("Invalid forAccounts array, expected string items");
      };
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid forAccounts field, expected array");
    };

    #ok({
      codeCount = codeCount;
      useCount = useCount;
      forAccounts = forAccounts;
    });
  };

};
