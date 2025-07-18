import CID "mo:cid";
import Result "mo:base/Result";
import DID "mo:did";

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
