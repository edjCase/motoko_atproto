import CID "mo:cid";
import TID "mo:tid";
import DID "mo:did";

module {
    public type UnsignedCommit = {
        did : DID.Plc.DID;
        version : Nat; // Always 3 for current format
        data : CID.CID; // Points to MST root
        rev : TID.TID; // Timestamp/revision
        prev : ?CID.CID; // Previous commit (usually null)
    };

    public type Commit = UnsignedCommit and {
        sig : Blob; // Cryptographic signature
    };
};
