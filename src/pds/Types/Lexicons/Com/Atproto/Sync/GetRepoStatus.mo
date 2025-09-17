import Json "mo:json@1";
import Result "mo:core@1/Result";
import DID "mo:did@3";

module {
  // com.atproto.sync.getRepoStatus
  // Get the hosting status for a repository, on this server. Expected to be implemented by PDS and Relay.

  public type Params = {
    did : DID.DID;
  };

  public type RepoStatus = {
    #takendown;
    #suspended;
    #deleted;
    #deactivated;
    #desynchronized;
    #throttled;
  };

  public type Response = {
    did : DID.DID;
    active : Bool;
    status : ?RepoStatus;
    rev : ?Text;
  };

  public type Error = {
    #repoNotFound;
  };

  public func toJson(response : Response) : Json.Json {
    let status = switch (response.status) {
      case (?#takendown) { #string("takendown") };
      case (?#suspended) { #string("suspended") };
      case (?#deleted) { #string("deleted") };
      case (?#deactivated) { #string("deactivated") };
      case (?#desynchronized) { #string("desynchronized") };
      case (?#throttled) { #string("throttled") };
      case (null) { #null_ };
    };

    #object_([
      ("did", #string(DID.toText(response.did))),
      ("active", #bool(response.active)),
      ("status", status),
      (
        "rev",
        switch (response.rev) {
          case (?r) { #string(r) };
          case (null) { #null_ };
        },
      ),
    ]);
  };

};
