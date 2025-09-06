import DID "mo:did@2";
import CID "mo:cid@1";
import TID "mo:tid@1";
import DagCbor "mo:dag-cbor@2";
import AtUri "./AtUri";
import DIDModule "../DID"

module {

  public type RepositoryWithoutDID = {
    head : CID.CID; // CID of current commit
    rev : TID.TID; // TID timestamp
    active : Bool;
    status : ?Text; // Optional status if not active
  };

  public type Repository = RepositoryWithoutDID and {
    did : DID.Plc.DID;
  };
};
