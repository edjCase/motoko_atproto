import CID "mo:cid@1";
import Result "mo:core@1/Result";
import DID "mo:did@3";

module {
  // com.atproto.sync.getBlob
  // Get a blob associated with a given account. Returns the full blob as originally uploaded. Does not require auth; implemented by PDS.

  public type Params = {
    did : DID.DID;
    cid : CID.CID;
  };

  public type Error = {
    #blobNotFound;
    #repoNotFound;
    #repoTakendown;
    #repoSuspended;
    #repoDeactivated;
  };

  // Output is binary blob data (*/*), so we use Blob type
  public type Response = Blob;

};
