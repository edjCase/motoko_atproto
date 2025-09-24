import Pds "../pds/Pds";

persistent actor {

  public type PdsInfo = {
    deployer : Principal;
    deployedAt : Time.Time;
    status : InitializationStatus;
  };

  public type InitializationStatus = {
    #initializing;
    #initialized : {
      initializedAt : Time.Time;
    };
    #initializationFailed : {
      reason : Text;
      failedAt : Time.Time;
    };
  };

  var pdsMap = PureMap.empty<Principal, PdsInfo>();

  public shared ({ caller }) func deploy() : async Result.Result<(), Text> {
    let pds = await Pds.Pds();
    // TODO error handling

    let pdsPrincipal = Principal.fromActor(pds);
    let pdsInfo = {
      deployer = caller;
      deployedAt = Time.now();
      status = #initializing;
    };
    pdsMap := PureMap.put(
      pdsMap,
      pdsPrincipal,
      pdsInfo,
    );
    let status = await* initializeInternal(pds);

    pdsMap := PureMap.put(
      pdsMap,
      pdsPrincipal,
      {
        pdsInfo with
        status = status
      },
    );
  };

  public shared ({ caller }) func initialize(pdsPrincipal : Principal) : async Result.Result<(), Text> {
    let ?pdsInfo = PureMap.get(pdsMap, pdsPrincipal) else return #err("PDS not found");
    if (pdsInfo.deployer != caller) {
      return #err("Only the initial deployer can initialize the PDS");
    };
    switch (pdsInfo.status) {
      case (#initialized(_)) return #err("PDS is already initialized");
      case (#initializationFailed(_, _)) ();
      case (#initializing) return #err("PDS is already initializing");
    };
    let pds = actor (pdsPrincipal) : Pds.Pds;
    let status = await* initializeInternal(pds);

    pdsMap := PureMap.put(
      pdsMap,
      pdsPrincipal,
      {
        pdsInfo with
        status = status
      },
    );
  };

  private func initializeInternal(
    pds : Pds.Pds
  ) : async* InitializationStatus {
    let status = try {

      switch (await* pds.initialize()) {
        case (#ok(())) #initialized({
          initializedAt = Time.now();
        });
        case (#err(e)) #initializationFailed({
          reason = e;
          failedAt = Time.now();
        });
      };

    } catch (e) {
      #initializationFailed({
        reason = "Initialization failed: " # Error.message(e);
        failedAt = Time.now();
      });
    };
  };
};
