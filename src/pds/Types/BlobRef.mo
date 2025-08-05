import CID "mo:cid";
import Json "mo:json";

module {

  /// Blob reference as returned by upload
  public type BlobRef = {
    /// CID reference to blob (with raw multicodec)
    ref : CID.CID;
    /// MIME type of the blob
    mimeType : Text;
    /// Size of the blob in bytes
    size : Nat;
  };

  public func toJson(blobRef : BlobRef) : Json.Json {
    #object_([
      ("$type", #string("blob")),
      ("ref", #object_([("$link", #string(CID.toText(blobRef.ref)))])),
      ("mimeType", #string(blobRef.mimeType)),
      ("size", #number(#int(blobRef.size))),
    ]);
  };
};
