import DID "mo:did";
import CID "mo:cid";
import TID "mo:tid";
import DagCbor "mo:dag-cbor";
import AtUri "../../../../AtUri";
import Json "mo:json";
import Result "mo:new-base/Result";
import Int "mo:new-base/Int";
import BaseX "mo:base-x-encoder";
import Blob "mo:new-base/Blob";
import BlobRef "../../../../BlobRef";

module {

  /// Request type for uploading a blob (raw binary data)
  public type Request = {
    /// The raw blob data to upload
    data : Blob;
    /// Mime type of the blob (e.g. "image/png", "application/json")
    mimeType : Text;
  };

  /// Response from a successful blob upload
  public type Response = {
    /// The blob reference metadata
    blob : BlobRef.BlobRef;
  };

  public func toJson(response : Response) : Json.Json {
    #object_([
      (
        "blob",
        BlobRef.toJson(response.blob),
      ),
    ]);
  };

};
