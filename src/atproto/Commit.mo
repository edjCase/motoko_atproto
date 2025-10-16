import CID "mo:cid@1";
import TID "mo:tid@1";
import DID "mo:did@3";

module {
  public type UnsignedCommit = {
    did : DID.Plc.DID;
    version : Nat;
    data : CID.CID; // Points to MST root
    rev : TID.TID; // Timestamp/revision
    prev : ?CID.CID; // Previous commit
  };

  public type Commit = UnsignedCommit and {
    sig : Blob; // signature
  };
};
