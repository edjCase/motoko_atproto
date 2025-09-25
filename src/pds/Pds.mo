import Text "mo:core@1/Text";
import Result "mo:core@1/Result";
import XrpcRouter "./XrpcRouter";
import WellKnownRouter "./WellKnownRouter";
import RouterMiddleware "mo:liminal@1/Middleware/Router";
import CompressionMiddleware "mo:liminal@1/Middleware/Compression";
import CORSMiddleware "mo:liminal@1/Middleware/CORS";
import Liminal "mo:liminal@1";
import Router "mo:liminal@1/Router";
import RepositoryHandler "Handlers/RepositoryHandler";
import KeyHandler "Handlers/KeyHandler";
import ServerInfoHandler "Handlers/ServerInfoHandler";
import DIDDirectoryHandler "Handlers/DIDDirectoryHandler";
import ServerInfo "ServerInfo";
import DID "mo:did@3";
import TID "mo:tid@1";
import CID "mo:cid@1";
import PureMap "mo:core@1/pure/Map";
import Json "mo:json@1";
import Principal "mo:core@1/Principal";
import CAR "mo:car@1";
import CarUtil "CarUtil";
import PdsInterface "./PdsInterface";

shared ({ caller = deployer }) persistent actor class Pds(
  initData : {
    owner : Principal;
  }
) : async PdsInterface.Actor = this {
  var owner = initData.owner;

  transient let tidGenerator = TID.Generator();

  var repositoryStableData : ?RepositoryHandler.StableData = null;
  var serverInfoStableData : ?ServerInfoHandler.StableData = null;
  var keyHandlerStableData : KeyHandler.StableData = {
    verificationDerivationPath = ["\00"]; // TODO: configure properly
  };

  // Handlers
  transient var keyHandler = KeyHandler.Handler(keyHandlerStableData);
  transient var serverInfoHandler = ServerInfoHandler.Handler(serverInfoStableData);
  transient var didDirectoryHandler = DIDDirectoryHandler.Handler(keyHandler);
  transient var repositoryHandler = RepositoryHandler.Handler(
    repositoryStableData,
    keyHandler,
    serverInfoHandler,
    tidGenerator,
  );

  // Routers
  transient var xrpcRouter = XrpcRouter.Router(
    repositoryHandler,
    serverInfoHandler,
    keyHandler,
  );
  transient var wellKnownRouter = WellKnownRouter.Router(
    serverInfoHandler,
    keyHandler,
  );

  system func preupgrade() {
    keyHandlerStableData := keyHandler.toStableData();
    serverInfoStableData := serverInfoHandler.toStableData();
    repositoryStableData := repositoryHandler.toStableData();
  };

  system func postupgrade() {
    keyHandler := KeyHandler.Handler(keyHandlerStableData);
    serverInfoHandler := ServerInfoHandler.Handler(serverInfoStableData);
    didDirectoryHandler := DIDDirectoryHandler.Handler(keyHandler);
    repositoryHandler := RepositoryHandler.Handler(
      repositoryStableData,
      keyHandler,
      serverInfoHandler,
      tidGenerator,
    );
    xrpcRouter := XrpcRouter.Router(
      repositoryHandler,
      serverInfoHandler,
      keyHandler,
    );
    wellKnownRouter := WellKnownRouter.Router(serverInfoHandler, keyHandler);
  };

  transient let routerConfig : RouterMiddleware.Config = {
    prefix = null;
    identityRequirement = null;
    routes = [
      Router.getAsyncUpdate("/xrpc/{nsid}", xrpcRouter.routeGet),
      Router.postAsyncUpdate("/xrpc/{nsid}", xrpcRouter.routePost),
      Router.getAsyncUpdate("/.well-known/did.json", wellKnownRouter.getDidDocument),
      Router.getUpdate("/.well-known/ic-domains", wellKnownRouter.getIcDomains),
      Router.getUpdate("/.well-known/atproto-did", wellKnownRouter.getAtprotoDid),
    ];
  };

  // Http App
  transient let app = Liminal.App({
    middleware = [
      CompressionMiddleware.default(),
      CORSMiddleware.new({
        CORSMiddleware.defaultOptions with
        allowOrigins = [];
        allowHeaders = [];
        allowMethods = [#get, #post];
      }),
      RouterMiddleware.new(routerConfig),
    ];
    errorSerializer = Liminal.defaultJsonErrorSerializer;
    candidRepresentationNegotiator = Liminal.defaultCandidRepresentationNegotiator;
    logger = Liminal.buildDebugLogger(#info);
  });

  // Http server methods
  public query func http_request(request : Liminal.RawQueryHttpRequest) : async Liminal.RawQueryHttpResponse {
    app.http_request(request);
  };

  public func http_request_update(request : Liminal.RawUpdateHttpRequest) : async Liminal.RawUpdateHttpResponse {
    await* app.http_request_update(request);
  };

  // Candid API methods
  public shared ({ caller }) func initialize(request : PdsInterface.InitializeRequest) : async Result.Result<(), Text> {
    if (caller != owner and caller != deployer) {
      return #err("Only the owner or deployer can initialize the PDS");
    };
    // TODO prevent re-initialization?
    let (plcIndentifier, repository) : (DID.Plc.DID, ?RepositoryHandler.RepositoryWithData) = switch (request.plc) {
      case (#new(createRequest)) {
        switch (await* didDirectoryHandler.create(createRequest)) {
          case (#ok(did)) (did, null);
          case (#err(e)) return #err("Failed to create PLC identifier: " # e);
        };
      };
      case (#id(id)) {
        switch (DID.Plc.fromText(id)) {
          case (#ok(did)) (did, null);
          case (#err(e)) return #err("Invalid PLC identifier '" # id # "': " # e);
        };
      };
      case (#car(carBlob)) {
        switch (CAR.fromBytes(carBlob.vals())) {
          case (#ok(parsedFile)) switch (CarUtil.buildRepository(parsedFile)) {
            case (#ok((did, repo))) (did, ?repo);
            case (#err(error)) return #err("Failed to build repository from CAR file: " # error);
          };
          case (#err(error)) return #err("Failed to parse CAR file: " # error);
        };
      };
    };
    serverInfoHandler.set({
      hostname = request.hostname;
      plcIdentifier = plcIndentifier;
      handlePrefix = request.handlePrefix;
    });
    switch (await* repositoryHandler.initialize(repository)) {
      case (#ok(_)) #ok;
      case (#err(e)) return #err("Failed to create repository: " # e);
    };
  };

};
