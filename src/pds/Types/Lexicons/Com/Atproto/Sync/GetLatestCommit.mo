import CID "mo:cid@1";
import Json "mo:json@1";
import Result "mo:base/Result";
import DID "mo:did@2";

module {
  // com.atproto.sync.getLatestCommit
  // Get the current commit CID & revision of the specified repo. Does not require auth.

  public type Params = {
    did : DID.DID;
  };

  public type Response = {
    cid : CID.CID;
    rev : Text;
  };

  public type Error = {
    #repoNotFound;
    #repoTakendown;
    #repoSuspended;
    #repoDeactivated;
  };

  public func toJson(response : Response) : Json.Json {
    #object_([
      ("cid", #string(CID.toText(response.cid))),
      ("rev", #string(response.rev)),
    ]);
  };

};
