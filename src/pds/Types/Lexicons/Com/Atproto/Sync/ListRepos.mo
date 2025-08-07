import CID "mo:cid";
import Json "mo:json";
import DID "mo:did";
import Array "mo:core/Array";

module {
  // com.atproto.sync.listRepos
  // Enumerates all the DID, rev, and commit CID for all repos hosted by this service. Does not require auth; implemented by PDS and Relay.

  public type Params = {
    limit : ?Nat;
    cursor : ?Text;
  };

  public type RepoStatus = {
    #takendown;
    #suspended;
    #deleted;
    #deactivated;
    #desynchronized;
    #throttled;
  };

  public type Repo = {
    did : DID.DID;
    head : CID.CID;
    rev : Text;
    active : ?Bool;
    status : ?RepoStatus;
  };

  public type Response = {
    cursor : ?Text;
    repos : [Repo];
  };

  public func toJson(response : Response) : Json.Json {
    let reposJson = response.repos |> Array.map(
      _,
      func(repo : Repo) : Json.Json {
        let status = switch (repo.status) {
          case (?#takendown) { #string("takendown") };
          case (?#suspended) { #string("suspended") };
          case (?#deleted) { #string("deleted") };
          case (?#deactivated) { #string("deactivated") };
          case (?#desynchronized) { #string("desynchronized") };
          case (?#throttled) { #string("throttled") };
          case (null) { #null_ };
        };

        #object_([
          ("did", #string(DID.toText(repo.did))),
          ("head", #string(CID.toText(repo.head))),
          ("rev", #string(repo.rev)),
          (
            "active",
            switch (repo.active) {
              case (?a) { #bool(a) };
              case (null) { # null };
            },
          ),
          ("status", status),
        ]);
      },
    );

    #object_([(
      "repos",
      #array_(reposJson),
      (
        "cursor",
        switch (response.cursor) {
          case (?c) { #string(c) };
          case (null) { #null_ };
        },
      ),
    )]);
  };

};
