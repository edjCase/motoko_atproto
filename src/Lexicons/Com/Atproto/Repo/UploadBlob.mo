import Json "mo:json@1";
import Blob "mo:core@1/Blob";
import BlobRef "../../../BlobRef";

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
