import CID "mo:cid";
import Json "mo:json";

module {

  public type Response = {
    activated : Bool;
    validDid : Bool;
    repoCommit : CID.CID;
    repoRev : Text;
    repoBlocks : Nat;
    indexedRecords : Nat;
    privateStateValues : Nat;
    expectedBlobs : Nat;
    importedBlobs : Nat;
  };

  public func toJson(response : Response) : Json.Json {
    #object_([
      ("activated", #bool(response.activated)),
      ("validDid", #bool(response.validDid)),
      ("repoCommit", #string(CID.toText(response.repoCommit))),
      ("repoRev", #string(response.repoRev)),
      ("repoBlocks", #number(#int(response.repoBlocks))),
      ("indexedRecords", #number(#int(response.indexedRecords))),
      ("privateStateValues", #number(#int(response.privateStateValues))),
      ("expectedBlobs", #number(#int(response.expectedBlobs))),
      ("importedBlobs", #number(#int(response.importedBlobs))),
    ]);
  };

};
