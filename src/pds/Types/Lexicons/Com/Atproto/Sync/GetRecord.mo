import Result "mo:base/Result";
import DID "mo:did";

module {
    // com.atproto.sync.getRecord
    // Get data blocks needed to prove the existence or non-existence of record in the current version of repo. Does not require auth.

    public type Params = {
        did : DID.DID;
        collection : Text;
        rkey : Text;
    };

    public type Error = {
        #recordNotFound;
        #repoNotFound;
        #repoTakendown;
        #repoSuspended;
        #repoDeactivated;
    };

    // Output is CAR file data (application/vnd.ipld.car), so we use Blob type
    public type Response = Blob;

};
