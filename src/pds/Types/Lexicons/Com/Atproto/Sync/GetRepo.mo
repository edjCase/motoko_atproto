import Result "mo:base/Result";
import DID "mo:did@2";

module {
  // com.atproto.sync.getRepo
  // Download a repository export as CAR file. Optionally only a 'diff' since a previous revision. Does not require auth; implemented by PDS.

  public type Params = {
    did : DID.DID;
    since : ?Text;
  };

  public type Error = {
    #repoNotFound;
    #repoTakendown;
    #repoSuspended;
    #repoDeactivated;
  };

  // Output is CAR file data (application/vnd.ipld.car), so we use Blob type
  public type Response = Blob;

};
