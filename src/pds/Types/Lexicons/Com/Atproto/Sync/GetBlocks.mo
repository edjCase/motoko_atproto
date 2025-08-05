import CID "mo:cid";
import Result "mo:base/Result";
import DID "mo:did";

module {
  // com.atproto.sync.getBlocks
  // Get data blocks from a given repo, by CID. For example, intermediate MST nodes, or records. Does not require auth; implemented by PDS.

  public type Params = {
    did : DID.DID;
    cids : [CID.CID];
  };

  public type Error = {
    #blockNotFound;
    #repoNotFound;
    #repoTakendown;
    #repoSuspended;
    #repoDeactivated;
  };

  // Output is CAR file data (application/vnd.ipld.car), so we use Blob type
  public type Response = Blob;

};
