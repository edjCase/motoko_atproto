import CID "mo:cid@1";
import Commit "Commit";
import DagCbor "mo:dag-cbor@2";
import Sha256 "mo:sha2@0/Sha256";
import Text "mo:core@1/Text";
import Runtime "mo:core@1/Runtime";
import MerkleNode "MerkleNode";
import Order "mo:core@1/Order";
import Blob "mo:core@1/Blob";
import DagCborBuilder "./DagCborBuilder";

module {

  public func compare(cid1 : CID.CID, cid2 : CID.CID) : Order.Order {
    if (cid1 == cid2) return #equal;

    let hash1 = CID.getHash(cid1);
    let hash2 = CID.getHash(cid2);
    Blob.compare(hash1, hash2);
  };

  public func fromBlob(blob : Blob) : CID.CID {
    let hash = Sha256.fromBlob(#sha256, blob);
    #v1({
      codec = #raw;
      hashAlgorithm = #sha2256;
      hash = hash;
    });
  };

  public func fromRecord(key : Text, value : DagCbor.Value) : CID.CID {
    fromDagCbor(DagCborBuilder.fromRecord(key, value));
  };

  public func fromUnsignedCommit(commit : Commit.UnsignedCommit) : CID.CID {
    fromDagCbor(DagCborBuilder.fromUnsignedCommit(commit));
  };

  public func fromCommit(commit : Commit.Commit) : CID.CID {
    fromDagCbor(DagCborBuilder.fromCommit(commit));
  };

  public func fromMSTNode(node : MerkleNode.Node) : CID.CID {
    fromDagCbor(DagCborBuilder.fromMSTNode(node));
  };

  func fromDagCbor(cbor : DagCbor.Value) : CID.CID {
    let bytes = switch (DagCbor.toBytes(cbor)) {
      case (#ok(blob)) blob;
      case (#err(e)) Runtime.trap("Failed to encode commit to CBOR: " # debug_show (e));
    };
    // Generate CID from bytes
    let hash = Sha256.fromArray(#sha256, bytes);
    #v1({
      codec = #dagCbor;
      hashAlgorithm = #sha2256;
      hash = hash;
    });
  };
};
