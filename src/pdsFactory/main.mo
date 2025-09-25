import Pds "../pds/Pds";
import PdsInterface "../pds/PdsInterface";
import Time "mo:core@1/Time";
import PureMap "mo:core@1/pure/Map";
import Result "mo:core@1/Result";
import Error "mo:core@1/Error";
import Principal "mo:core@1/Principal";

persistent actor {

  public type PdsInfo = {
    deployer : Principal;
    deployedAt : Time.Time;
    status : InitializationStatus;
  };

  public type FinalInitializationStatus = {
    #initialized : {
      initializedAt : Time.Time;
    };
    #initializationFailed : {
      reason : Text;
      failedAt : Time.Time;
    };
  };

  public type InitializationStatus = FinalInitializationStatus or {
    #initializing;
  };

  var pdsMap = PureMap.empty<Principal, PdsInfo>();

  public shared ({ caller }) func deploy(
    canisterId : ?Principal,
    initializeRequest : PdsInterface.InitializeRequest,
  ) : async Result.Result<(), Text> {
    let installArgs = switch (canisterId) {
      case (?canisterId) #install(canisterId);
      case (null) #new({
        settings = ?{
          compute_allocation = null;
          controllers = ?[caller];
          freezing_threshold = null;
          memory_allocation = null;
        };
      });
    };
    let pds = await (system Pds.Pds)(installArgs)({
      owner = caller;
    });

    // TODO error handling

    let pdsPrincipal = Principal.fromActor(pds);
    let pdsInfo = {
      deployer = caller;
      deployedAt = Time.now();
      status = #initializing;
    };
    pdsMap := PureMap.add(
      pdsMap,
      Principal.compare,
      pdsPrincipal,
      pdsInfo,
    );
    let status = await* initializeInternal(pds, initializeRequest);

    pdsMap := PureMap.add(
      pdsMap,
      Principal.compare,
      pdsPrincipal,
      {
        pdsInfo with
        status = status
      },
    );
    switch (status) {
      case (#initialized(_)) #ok;
      case (#initializationFailed(failure)) #err("PDS deployed but initialization failed: " # failure.reason);
    };
  };

  public shared ({ caller }) func initialize(
    pdsPrincipal : Principal,
    initializeRequest : PdsInterface.InitializeRequest,
  ) : async Result.Result<(), Text> {
    let ?pdsInfo = PureMap.get(pdsMap, Principal.compare, pdsPrincipal) else return #err("PDS not found");
    if (pdsInfo.deployer != caller) {
      return #err("Only the initial deployer can initialize the PDS");
    };
    switch (pdsInfo.status) {
      case (#initialized(_)) return #err("PDS is already initialized");
      case (#initializationFailed(_)) ();
      case (#initializing) return #err("PDS is already initializing");
    };
    let pds = actor (Principal.toText(pdsPrincipal)) : Pds.Pds;
    let status = await* initializeInternal(pds, initializeRequest);

    pdsMap := PureMap.add(
      pdsMap,
      Principal.compare,
      pdsPrincipal,
      {
        pdsInfo with
        status = status
      },
    );
    #ok;
  };

  private func initializeInternal(
    pds : Pds.Pds,
    initializeRequest : PdsInterface.InitializeRequest,
  ) : async* FinalInitializationStatus {
    try {
      switch (await pds.initialize(initializeRequest)) {
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
