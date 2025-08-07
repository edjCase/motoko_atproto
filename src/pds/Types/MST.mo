import Blob "mo:core/Blob";
import CID "mo:cid";
import Nat "mo:core/Nat";
import Text "mo:core/Text";

module {
  public type Node = {
    leftSubtreeCID : ?CID.CID;
    entries : [TreeEntry];
  };

  public type TreeEntry = {
    prefixLength : Nat; // Length of the common prefix
    keySuffix : [Nat8]; // Suffix of the key after the common prefix
    valueCID : CID.CID; // CID pointing to the value record
    subtreeCID : ?CID.CID; // Right child CID, or null if a leaf
  };

  public type KeyValue = {
    key : [Nat8]; // Full key as byte array
    value : CID.CID; // CID pointing to record
  };

  // Create an empty MST (single empty node)
  public func empty() : Node {
    {
      leftSubtreeCID = null;
      entries = [];
    };
  };

  // Convert text path to byte array
  public func pathToKey(path : Text) : [Nat8] {
    Text.encodeUtf8(path) |> Blob.toArray(_);
  };

};
