import DID "mo:did@2";
import CID "mo:cid@1";
import TID "mo:tid@1";
import DagCbor "mo:dag-cbor@2";
import AtUri "../../../../AtUri";
import Json "mo:json@1";
import Result "mo:core@1/Result";
import Array "mo:core@1/Array";
import Nat "mo:core@1/Nat";
import Text "mo:core@1/Text";

module {

  /// Request type for listing repository blobs
  public type Request = {
    /// The DID of the repo
    did : DID.Plc.DID;

    /// Optional revision of the repo to list blobs since
    since : ?TID.TID;

    /// The number of blob CIDs to return (1-1000, default 500)
    limit : ?Nat;

    /// Pagination cursor
    cursor : ?Text;
  };

  /// Response from a successful list blobs operation
  public type Response = {
    /// Pagination cursor for next page
    cursor : ?Text;

    /// Array of blob CIDs
    cids : [CID.CID];
  };

  public func toJson(response : Response) : Json.Json {

    let cidsJson = response.cids |> Array.map<CID.CID, Json.Json>(
      _,
      func(cid : CID.CID) : Json.Json = #string(CID.toText(cid)),
    );

    #object_([
      (
        "cursor",
        switch (response.cursor) {
          case (?cursor) #string(cursor);
          case (null) #null_;
        },
      ),
      ("cids", #array(cidsJson)),
    ]);
  };

};
