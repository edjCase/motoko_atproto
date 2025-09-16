import CID "mo:cid@1";
import Commit "Types/Commit";
import DID "mo:did@3";
import TID "mo:tid@1";
import DagCbor "mo:dag-cbor@2";
import Sha256 "mo:sha2/Sha256";
import BaseX "mo:base-x-encoder@2";
import Text "mo:core@1/Text";
import Array "mo:core@1/Array";
import Runtime "mo:core@1/Runtime";
import MST "Types/MST";
import Nat8 "mo:core@1/Nat8";

module {

  public func fromBlob(blob : Blob) : CID.CID {
    let hash = Sha256.fromBlob(#sha256, blob);
    #v1({
      codec = #raw;
      hashAlgorithm = #sha2256;
      hash = hash;
    });
  };

  public func fromRecord(key : Text, value : DagCbor.Value) : CID.CID {
    let cborMap = [
      ("key", #text(key)),
      ("value", value),
    ];
    fromDagCbor(#map(cborMap));
  };

  public func fromUnsignedCommit(commit : Commit.UnsignedCommit) : CID.CID {
    let cborMap = unsignedCommitToCbor(commit);

    fromDagCbor(#map(cborMap));
  };

  public func fromCommit(commit : Commit.Commit) : CID.CID {
    let unsignedCborMap = unsignedCommitToCbor(commit);
    let cborMap = Array.concat(
      unsignedCborMap,
      [(
        "sig",
        #text(BaseX.toBase64(commit.sig.vals(), #url({ includePadding = false }))),
      )],
    );

    fromDagCbor(#map(cborMap));
  };

  public func fromMSTNode(node : MST.Node) : CID.CID {
    // Convert left CID
    let leftCbor : DagCbor.Value = switch (node.leftSubtreeCID) {
      case (null) #null_;
      case (?cid) #text(CID.toText(cid));
    };

    // Convert entries array
    let entriesCbor = node.entries
    |> Array.map<MST.TreeEntry, DagCbor.Value>(
      _,
      func(entry : MST.TreeEntry) : DagCbor.Value {
        let keyCbor = entry.keySuffix
        |> Array.map<Nat8, DagCbor.Value>(_, func(byte : Nat8) : DagCbor.Value = #int(Nat8.toNat(byte)));

        let rightCbor : DagCbor.Value = switch (entry.subtreeCID) {
          case (null) #null_;
          case (?cid) #text(CID.toText(cid));
        };

        #map([
          ("p", #int(entry.prefixLength)),
          ("k", #array(keyCbor)),
          ("v", #text(CID.toText(entry.valueCID))),
          ("t", rightCbor),
        ]);
      },
    );

    let cborValue = #map([
      ("l", leftCbor),
      ("e", #array(entriesCbor)),
    ]);
    fromDagCbor(cborValue);
  };

  func unsignedCommitToCbor(unsigned : Commit.UnsignedCommit) : [(Text, DagCbor.Value)] {
    [
      ("did", #text(DID.Plc.toText(unsigned.did))),
      ("version", #int(3)), // Current version is always 3
      ("data", #text(CID.toText(unsigned.data))),
      ("rev", #text(TID.toText(unsigned.rev))),
      (
        "prev",
        switch (unsigned.prev) {
          case (null) #null_;
          case (?cid) #text(CID.toText(cid));
        },
      ),
    ];
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
