import DagCbor "mo:dag-cbor@2";
import Json "mo:json@1";
import JsonDagCborMapper "../../../../../JsonDagCborMapper";

module {

  public type Status = {
    #takendown;
    #suspended;
    #deactivated;
  };

  public type Response = {
    accessJwt : Text;
    refreshJwt : Text;
    handle : Text;
    did : Text; // DID string
    didDoc : ?DagCbor.Value;
    active : ?Bool;
    status : ?Status;
  };

  public type Error = {
    #accountTakedown : { message : Text };
  };

  public func toJson(response : Response) : Json.Json {
    let didDocJson = switch (response.didDoc) {
      case (?didDoc) JsonDagCborMapper.fromDagCbor(didDoc);
      case (null) #null_;
    };

    let activeJson = switch (response.active) {
      case (?active) #bool(active);
      case (null) #null_;
    };

    let statusJson = switch (response.status) {
      case (?#takendown) #string("takendown");
      case (?#suspended) #string("suspended");
      case (?#deactivated) #string("deactivated");
      case (null) #null_;
    };

    #object_([
      ("accessJwt", #string(response.accessJwt)),
      ("refreshJwt", #string(response.refreshJwt)),
      ("handle", #string(response.handle)),
      ("did", #string(response.did)),
      ("didDoc", didDocJson),
      ("active", activeJson),
      ("status", statusJson),
    ]);
  };

};
