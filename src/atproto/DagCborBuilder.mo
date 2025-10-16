import Commit "Commit";
import DID "mo:did@3";
import TID "mo:tid@1";
import DagCbor "mo:dag-cbor@2";
import BaseX "mo:base-x-encoder@2";
import Text "mo:core@1/Text";
import Array "mo:core@1/Array";
import MerkleNode "MerkleNode";
import Nat8 "mo:core@1/Nat8";
import DynamicArray "mo:xtended-collections@0/DynamicArray";
import Blob "mo:core@1/Blob";

module {

  public func fromRecord(key : Text, value : DagCbor.Value) : DagCbor.Value {
    #map([
      ("key", #text(key)),
      ("value", value),
    ]);
  };

  public func fromUnsignedCommit(unsigned : Commit.UnsignedCommit) : DagCbor.Value {
    #map(DynamicArray.toArray(fromUnsignedCommitInternal(unsigned)));
  };

  public func fromCommit(commit : Commit.Commit) : DagCbor.Value {
    let unsignedCommitFields = fromUnsignedCommitInternal(commit);
    unsignedCommitFields.add((
      "sig",
      #bytes(Blob.toArray(commit.sig)),
    ));

    #map(DynamicArray.toArray(unsignedCommitFields));
  };

  private func fromUnsignedCommitInternal(unsigned : Commit.UnsignedCommit) : DynamicArray.DynamicArray<(Text, DagCbor.Value)> {
    let fields = DynamicArray.DynamicArray<(Text, DagCbor.Value)>(6);
    fields.add(("did", #text(DID.Plc.toText(unsigned.did))));
    fields.add(("version", #int(unsigned.version)));
    fields.add(("data", #cid(unsigned.data)));
    fields.add(("rev", #text(TID.toText(unsigned.rev))));
    fields.add((
      "prev",
      switch (unsigned.prev) {
        case (null) #null_;
        case (?cid) #cid(cid);
      },
    ));
    fields;
  };

  public func fromMSTNode(node : MerkleNode.Node) : DagCbor.Value {
    // Convert left CID
    let leftCbor : DagCbor.Value = switch (node.leftSubtreeCID) {
      case (null) #null_;
      case (?cid) #cid(cid);
    };

    // Convert entries array
    let entriesCbor = node.entries
    |> Array.map<MerkleNode.TreeEntry, DagCbor.Value>(
      _,
      func(entry : MerkleNode.TreeEntry) : DagCbor.Value {

        let rightCbor : DagCbor.Value = switch (entry.subtreeCID) {
          case (null) #null_;
          case (?cid) #cid(cid);
        };

        #map([
          ("p", #int(entry.prefixLength)),
          ("k", #bytes(entry.keySuffix)),
          ("v", #cid(entry.valueCID)),
          ("t", rightCbor),
        ]);
      },
    );

    #map([
      ("l", leftCbor),
      ("e", #array(entriesCbor)),
    ]);
  };

};
