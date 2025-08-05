import Json "mo:json";
import DID "mo:did";
import Array "mo:base/Array";

module {
  // com.atproto.sync.listReposByCollection
  // Enumerates all the DIDs which have records with the given collection NSID.

  public type Params = {
    collection : Text;
    limit : ?Nat;
    cursor : ?Text;
  };

  public type Repo = {
    did : DID.DID;
  };

  public type Response = {
    cursor : ?Text;
    repos : [Repo];
  };

  public func toJson(response : Response) : Json.Json {
    let reposJson = Array.map<Repo, Json.Json>(
      response.repos,
      func(repo : Repo) : Json.Json {
        #object_([("did", #string(DID.toText(repo.did)))]);
      },
    );

    let fields = [("repos", #array_(reposJson))];

    let withCursor = switch (response.cursor) {
      case (?c) { fields # [("cursor", #string(c))] };
      case (null) { fields };
    };

    #object_(withCursor);
  };

};
