import Result "mo:core@1/Result";

module {
  public type Actor = actor {
    initialize(request : InitializeRequest) : async Result.Result<(), Text>;
  };

  public type InitializeRequest = {
    plc : PlcKind;
    hostname : Text;
    serviceSubdomain : ?Text;
  };

  public type PlcKind = {
    #new : CreatePlcRequest;
    #id : Text;
    #car : Blob;
  };

  public type CreatePlcRequest = {
    alsoKnownAs : [Text];
    services : [PlcService];
  };

  public type UpdatePlcRequest = {
    did : Text;
    alsoKnownAs : [Text];
    services : [PlcService];
  };

  public type PlcService = {
    id : Text;
    type_ : Text;
    endpoint : Text;
  };
};
