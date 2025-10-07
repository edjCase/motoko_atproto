import Pds "../pds/Pds";
import PdsInterface "../pds/PdsInterface";
import Time "mo:core@1/Time";
import PureMap "mo:core@1/pure/Map";
import Result "mo:core@1/Result";
import Error "mo:core@1/Error";
import Principal "mo:core@1/Principal";
import Iter "mo:core@1/Iter";
import DateTime "mo:datetime@1/DateTime";

persistent actor PdsFactory {

  public type PdsInfo = {
    owner : Principal;
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
    #initializing : {
      startedAt : Time.Time;
    };
    #notInitialized;
  };

  public type DeployRequest = {
    existingCanisterId : ?Principal;
    kind : {
      #installOnly;
      #installAndInitialize : PdsInterface.InitializeRequest;
    };
  };

  var pdsMap = PureMap.empty<Principal, PdsInfo>();

  public shared ({ caller }) func getDeployedInstances() : async [Principal] {
    pdsMap
    |> PureMap.entries(_)
    |> Iter.filterMap(
      _,
      func((id, info) : (Principal, PdsInfo)) : ?Principal {
        if (info.owner != caller) {
          return null;
        };
        ?id;
      },
    )
    |> Iter.toArray(_);
  };

  public shared ({ caller }) func upgrade(pdsPrincipal : Principal) : async Result.Result<(), Text> {
    let ?pdsInfo = PureMap.get(pdsMap, Principal.compare, pdsPrincipal) else return #err("PDS not found");
    if (pdsInfo.owner != caller) {
      return #err("Only the owner can upgrade the PDS");
    };
    try {
      let pdsActor = actor (Principal.toText(pdsPrincipal)) : Pds.Pds;
      ignore await (with cycles = 1_000_000_000_000) (system Pds.Pds)(#upgrade(pdsActor))({
        owner = caller;
      });
      #ok;
    } catch (e) {
      #err("Upgrade failed: " # Error.message(e));
    };
  };

  public shared ({ caller }) func deployPds(
    request : DeployRequest
  ) : async Result.Result<Principal, Text> {
    if (caller == Principal.anonymous()) {
      return #err("Anonymous caller is not allowed to deploy a PDS");
    };
    let installArgs = switch (request.existingCanisterId) {
      case (?canisterId) #install(canisterId);
      case (null) #new({
        settings = ?{
          compute_allocation = null;
          controllers = ?[caller, Principal.fromActor(PdsFactory)];
          freezing_threshold = null;
          memory_allocation = null;
        };
      });
    };
    let pds = await (with cycles = 1_200_000_000_000) (system Pds.Pds)(installArgs)({
      owner = caller;
    });

    // TODO error handling

    let pdsPrincipal = Principal.fromActor(pds);
    let pdsInfo = {
      owner = caller;
      deployedAt = Time.now();
      status = #notInitialized;
    };
    pdsMap := PureMap.add(
      pdsMap,
      Principal.compare,
      pdsPrincipal,
      pdsInfo,
    );
    switch (request.kind) {
      case (#installOnly) #ok(pdsPrincipal);
      case (#installAndInitialize(initializeRequest)) switch (await* initializeInternal(pds, pdsInfo, initializeRequest)) {
        case (#ok(())) #ok(pdsPrincipal);
        case (#err(e)) #err("Deploy successful but initialization failed: " # e);
      };
    };
  };

  public shared ({ caller }) func initializePds(
    pdsCanisterId : Principal,
    initializeRequest : PdsInterface.InitializeRequest,
  ) : async Result.Result<(), Text> {
    let ?pdsInfo = PureMap.get(pdsMap, Principal.compare, pdsCanisterId) else return #err("PDS not found");
    if (pdsInfo.owner != caller) {
      return #err("Only the owner can retry failed initialization the PDS");
    };
    switch (pdsInfo.status) {
      case (#initializationFailed(_) or #notInitialized) ();
      case (#initialized(_)) return #err("PDS is already initialized");
      case (#initializing({ startedAt })) return #err("PDS is already initializing. Started at " # DateTime.DateTime(startedAt).toText());
    };
    let pds = actor (Principal.toText(pdsCanisterId)) : Pds.Pds;

    await* initializeInternal(pds, pdsInfo, initializeRequest);
  };

  private func initializeInternal(
    pds : Pds.Pds,
    pdsInfo : PdsInfo,
    initializeRequest : PdsInterface.InitializeRequest,
  ) : async* Result.Result<(), Text> {

    let pdsPrincipal = Principal.fromActor(pds);
    pdsMap := PureMap.add(
      pdsMap,
      Principal.compare,
      pdsPrincipal,
      {
        pdsInfo with
        status = #initializing({
          startedAt = Time.now();
        });
      },
    );
    let status = try {
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
        reason = Error.message(e);
        failedAt = Time.now();
      });
    };

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
      case (#initializationFailed(failure)) #err(failure.reason);
    };
  };
};
