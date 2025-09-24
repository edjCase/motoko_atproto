import DID "mo:did@3";
import CID "mo:cid@1";
import TID "mo:tid@1";
import DagCbor "mo:dag-cbor@2";
import AtUri "./AtUri";

module {

  public type Repository = {
    head : CID.CID; // CID of current commit
    rev : TID.TID; // TID timestamp
    active : Bool;
    status : ?Text; // Optional status if not active
  };
};
