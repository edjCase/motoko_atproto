import Commit "Commit";
import DID "mo:did@3";
import TID "mo:tid@1";
import DagCbor "mo:dag-cbor@2";
import Text "mo:core@1/Text";
import Array "mo:core@1/Array";
import MerkleNode "MerkleNode";
import DynamicArray "mo:xtended-collections@0/DynamicArray";
import Blob "mo:core@1/Blob";

module {

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
    let fields = DynamicArray.DynamicArray<(Text, DagCbor.Value)>(2);

    // Only add "l" field if left subtree exists
    let leftSubtreeCIDCbor = switch (node.leftSubtreeCID) {
      case (?cid) #cid(cid);
      case (null) #null_;
    };
    fields.add(("l", leftSubtreeCIDCbor));

    // Convert entries array
    let entriesCbor = node.entries
    |> Array.map<MerkleNode.TreeEntry, DagCbor.Value>(
      _,
      func(entry : MerkleNode.TreeEntry) : DagCbor.Value {
        let entryFields = DynamicArray.DynamicArray<(Text, DagCbor.Value)>(4);

        entryFields.add(("p", #int(entry.prefixLength)));
        entryFields.add(("k", #bytes(entry.keySuffix)));
        entryFields.add(("v", #cid(entry.valueCID)));

        // Only add "t" field if right subtree exists
        let subtreeCIDCbor = switch (entry.subtreeCID) {
          case (?cid) #cid(cid);
          case (null) #null_;
        };
        entryFields.add(("t", subtreeCIDCbor));

        #map(DynamicArray.toArray(entryFields));
      },
    );

    fields.add(("e", #array(entriesCbor)));
    #map(DynamicArray.toArray(fields));
  };

};
