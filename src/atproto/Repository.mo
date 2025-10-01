import DID "mo:did@3";
import CID "mo:cid@1";
import TID "mo:tid@1";
import DagCbor "mo:dag-cbor@2";
import AtUri "./AtUri";

module {

  public type Repository = Repository.MetaData and {
    commits : PureMap.Map<TID.TID, Commit>;
    records : PureMap.Map<CID.CID, DagCbor.Value>;
    nodes : PureMap.Map<Text, MerkleNode.Node>;
    blobs : PureMap.Map<CID.CID, BlobRef>;
  };

  public type MetaData = {
    head : CID.CID; // CID of current commit
    rev : TID.TID; // TID timestamp
    active : Bool;
    status : ?Text; // Optional status if not active
  };
};
