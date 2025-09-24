import DID "mo:did@3";
import CID "mo:cid@1";
import TID "mo:tid@1";
import DagCbor "mo:dag-cbor@2";
import AtUri "../../../../AtUri";
import Json "mo:json@1";
import Result "mo:core@1/Result";
import JsonDagCborMapper "../../../../JsonDagCborMapper";

// com.atproto.repo.getRecord
module {

  /// Request type for getting a single repository record
  public type Request = {
    /// The handle or DID of the repo
    repo : DID.Plc.DID;

    /// The NSID of the record collection
    collection : Text;

    /// The Record Key
    rkey : Text;

    /// The CID of the version of the record. If not provided, returns the most recent version
    cid : ?CID.CID;
  };

  /// Response from a successful record retrieval
  public type Response = {
    /// AT-URI identifying the retrieved record
    uri : AtUri.AtUri;

    /// Content Identifier of the retrieved record
    cid : ?CID.CID;

    /// The record data
    value : DagCbor.Value;
  };

  public func toJson(response : Response) : Json.Json {

    let atUri = AtUri.toText(response.uri);
    let valueJson = JsonDagCborMapper.fromDagCbor(response.value);
    #object_([
      ("uri", #string(atUri)),
      (
        "cid",
        switch (response.cid) {
          case (?cid) #string(CID.toText(cid));
          case (null) #null_;
        },
      ),
      ("value", valueJson),
    ]);
  };

};
