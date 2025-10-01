import DID "mo:did@3";
import CID "mo:cid@1";
import TID "mo:tid@1";
import DagCbor "mo:dag-cbor@2";
import AtUri "./AtUri";
import PureMap "mo:core@1/pure/Map";
import MerkleNode "./MerkleNode";
import BlobRef "./BlobRef";
import Commit "./Commit";
import MerkleSearchTree "./MerkleSearchTree";
import Runtime "mo:core@1/Runtime";

module {

  public type MetaData = {
    head : CID.CID; // CID of the latest commit
    rev : TID.TID; // TID timestamp of the latest commit
    active : Bool;
    status : ?Text; // Optional status if not active
  };

  public type Repository = MetaData and {
    commits : PureMap.Map<TID.TID, Commit.Commit>;
    records : PureMap.Map<CID.CID, DagCbor.Value>;
    nodes : PureMap.Map<CID.CID, MerkleNode.Node>;
    blobs : PureMap.Map<CID.CID, BlobRef.BlobRef>;
  };

  public func buildMerkleSearchTree(repository : Repository) : MerkleSearchTree.MerkleSearchTree {
    // Get current commit to find root node
    let ?currentCommit = PureMap.get(
      repository.commits,
      TID.compare,
      repository.rev,
    ) else {
      Runtime.trap("Current commit not found in repository");
    };
    {
      root = currentCommit.data;
      nodes = repository.nodes;
    };
  };

};
