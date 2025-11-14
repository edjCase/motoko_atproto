import CID "mo:cid@1";
import AtUri "../AtUri";

module {

  /// A URI with a content-hash fingerprint.
  public type StrongRef = {
    /// Link to the resource
    uri : AtUri.AtUri;
    /// CID reference
    cid : CID.CID;
  };
};
