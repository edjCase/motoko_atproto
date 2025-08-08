import DagCbor "mo:dag-cbor";
import Json "mo:json";
import JsonDagCborMapper "../../../../../JsonDagCborMapper";
import DIDDocument "../../../../../Types/DIDDocument";

module {

  public type Status = {
    #takendown;
    #suspended;
    #deactivated;
  };

  public type Response = {
    handle : Text;
    did : Text; // DID string
    email : ?Text;
    emailConfirmed : ?Bool;
    emailAuthFactor : ?Bool;
    didDoc : ?DIDDocument.DIDDocument;
    active : ?Bool;
    status : ?Status;
  };

  public func toJson(response : Response) : Json.Json {
    let emailJson = switch (response.email) {
      case (?email) #string(email);
      case (null) #null_;
    };

    let emailConfirmedJson = switch (response.emailConfirmed) {
      case (?confirmed) #bool(confirmed);
      case (null) #null_;
    };

    let emailAuthFactorJson = switch (response.emailAuthFactor) {
      case (?authFactor) #bool(authFactor);
      case (null) #null_;
    };

    let didDocJson = switch (response.didDoc) {
      case (?didDoc) DIDDocument.toJson(didDoc);
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
      ("handle", #string(response.handle)),
      ("did", #string(response.did)),
      ("email", emailJson),
      ("emailConfirmed", emailConfirmedJson),
      ("emailAuthFactor", emailAuthFactorJson),
      ("didDoc", didDocJson),
      ("active", activeJson),
      ("status", statusJson),
    ]);
  };

};
