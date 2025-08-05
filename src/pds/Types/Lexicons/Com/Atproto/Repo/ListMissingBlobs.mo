import CID "mo:cid";
import AtUri "../../../../AtUri";
import Json "mo:json";
import Result "mo:new-base/Result";
import Array "mo:base/Array";
import Int "mo:base/Int";

module {

  public type Request = {
    limit : ?Nat;
    cursor : ?Text;
  };

  public type RecordBlob = {
    cid : CID.CID;
    recordUri : AtUri.AtUri;
  };

  public type Response = {
    cursor : ?Text;
    blobs : [RecordBlob];
  };

  public func toJson(response : Response) : Json.Json {
    let cursorJson = switch (response.cursor) {
      case (?cursor) #string(cursor);
      case (null) #null_;
    };

    let blobsJson = response.blobs |> Array.map<RecordBlob, Json.Json>(
      _,
      func(blob) {
        #object_([
          ("cid", #string(CID.toText(blob.cid))),
          ("recordUri", #string(AtUri.toText(blob.recordUri))),
        ]);
      },
    );

    #object_([
      ("cursor", cursorJson),
      ("blobs", #array(blobsJson)),
    ]);
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    let limit = switch (Json.getAsInt(json, "limit")) {
      case (#ok(l)) if (l >= 1 and l <= 1000) ?Int.abs(l) else return #err("Invalid limit, must be between 1 and 1000");
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid limit field, expected integer");
    };

    let cursor = switch (Json.getAsText(json, "cursor")) {
      case (#ok(c)) ?c;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid cursor field, expected string");
    };

    #ok({
      limit = limit;
      cursor = cursor;
    });
  };

};
