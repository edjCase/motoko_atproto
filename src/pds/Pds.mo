import Text "mo:core@1/Text";
import Result "mo:core@1/Result";
import XrpcRouter "./XrpcRouter";
import WellKnownRouter "./WellKnownRouter";
import RouterMiddleware "mo:liminal@2/Middleware/Router";
import CompressionMiddleware "mo:liminal@2/Middleware/Compression";
import CORSMiddleware "mo:liminal@2/Middleware/CORS";
import Liminal "mo:liminal@2";
import Router "mo:liminal@2/Router";
import RepositoryHandler "Handlers/RepositoryHandler";
import KeyHandler "Handlers/KeyHandler";
import ServerInfoHandler "Handlers/ServerInfoHandler";
import DIDDirectoryHandler "Handlers/DIDDirectoryHandler";
import DID "mo:did@3";
import TID "mo:tid@1";
import CID "mo:cid@1";
import Principal "mo:core@1/Principal";
import CAR "mo:car@1";
import CarUtil "CarUtil";
import PdsInterface "./PdsInterface";
import DateTime "mo:datetime@1/DateTime";
import Repository "../atproto/Repository";
import Option "mo:core@1/Option";
import RouteContext "mo:liminal@2/RouteContext";
import Route "mo:liminal@2/Route";

shared ({ caller = deployer }) persistent actor class Pds(
  initData : {
    owner : ?Principal;
  }
) : async PdsInterface.Actor = this {
  var owner = Option.get(initData.owner, deployer);

  var repositoryStableData : ?RepositoryHandler.StableData = null;
  var serverInfoStableData : ?ServerInfoHandler.StableData = null;
  var keyHandlerStableData : KeyHandler.StableData = {
    verificationDerivationPath = ["\00"]; // TODO: configure properly
  };

  type Handlers = {
    repositoryHandler : RepositoryHandler.Handler;
    serverInfoHandler : ServerInfoHandler.Handler;
    keyHandler : KeyHandler.Handler;
    didDirectoryHandler : DIDDirectoryHandler.Handler;
  };

  func buildRouters() : (XrpcRouter.Router, WellKnownRouter.Router, Handlers, () -> ()) {
    let tidGenerator = TID.Generator();
    let keyHandler = KeyHandler.Handler(keyHandlerStableData);
    let serverInfoHandler = ServerInfoHandler.Handler(serverInfoStableData);
    let didDirectoryHandler = DIDDirectoryHandler.Handler(keyHandler);
    let repositoryHandler = RepositoryHandler.Handler(
      repositoryStableData,
      keyHandler,
      serverInfoHandler,
      tidGenerator,
    );
    let handlers = {
      repositoryHandler = repositoryHandler;
      serverInfoHandler = serverInfoHandler;
      keyHandler = keyHandler;
      didDirectoryHandler = didDirectoryHandler;
    };
    let xrpcRouter = XrpcRouter.Router(
      repositoryHandler,
      serverInfoHandler,
      keyHandler,
    );
    let wellKnownRouter = WellKnownRouter.Router(serverInfoHandler, keyHandler);
    let dispose = func() {
      keyHandlerStableData := keyHandler.toStableData();
      serverInfoStableData := serverInfoHandler.toStableData();
      repositoryStableData := repositoryHandler.toStableData();
    };
    (xrpcRouter, wellKnownRouter, handlers, dispose);
  };

  func routeGet<system>(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {
    let (xrpcRouter, _, _, dispose) = buildRouters();
    let response = await* xrpcRouter.routeGet(routeContext);
    dispose();
    response;
  };

  func routePost<system>(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {
    let (xrpcRouter, _, _, dispose) = buildRouters();
    let response = await* xrpcRouter.routePost(routeContext);
    dispose();
    response;
  };

  func getDidDocument<system>(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {
    let (_, wellKnownRouter, _, dispose) = buildRouters();
    let response = await* wellKnownRouter.getDidDocument(routeContext);
    dispose();
    response;
  };

  func getIcDomains<system>(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
    let (_, wellKnownRouter, _, dispose) = buildRouters();
    let response = wellKnownRouter.getIcDomains<system>(routeContext);
    dispose();
    response;
  };

  func getAtprotoDid<system>(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
    let (_, wellKnownRouter, _, dispose) = buildRouters();
    let response = wellKnownRouter.getAtprotoDid<system>(routeContext);
    dispose();
    response;
  };

  transient let routerConfig : RouterMiddleware.Config = {
    prefix = null;
    identityRequirement = null;
    routes = [
      Router.getAsyncUpdate("/xrpc/{nsid}", routeGet),
      Router.postAsyncUpdate("/xrpc/{nsid}", routePost),
      Router.getAsyncUpdate("/.well-known/did.json", getDidDocument),
      Router.getUpdate("/.well-known/ic-domains", getIcDomains),
      Router.getUpdate("/.well-known/atproto-did", getAtprotoDid),
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
    logger = Liminal.buildDebugLogger(#verbose);
    urlNormalization = {
      pathIsCaseSensitive = false;
      preserveTrailingSlash = false;
      queryKeysAreCaseSensitive = false;
      removeEmptyPathSegments = true;
      resolvePathDotSegments = true;
      usernameIsCaseSensitive = false;
    };
  });

  // Http server methods
  public query func http_request(request : Liminal.RawQueryHttpRequest) : async Liminal.RawQueryHttpResponse {
    app.http_request(request);
  };

  public func http_request_update(request : Liminal.RawUpdateHttpRequest) : async Liminal.RawUpdateHttpResponse {
    await* app.http_request_update(request);
  };

  public shared ({ caller }) func post(message : Text) : async Result.Result<Text, Text> {
    if (caller != owner) {
      return #err("Only the owner can post to this PDS");
    };
    let now = DateTime.now();
    let createRecordRequest : RepositoryHandler.CreateRecordRequest = {
      collection = "app.bsky.feed.post";
      rkey = null;
      record = #map([
        ("$type", #text("app.bsky.feed.post")),
        ("text", #text(message)),
        ("createdAt", #text(now.toTextFormatted(#iso))),
      ]);
      validate = null;
      swapCommit = null;
    };
    let (_, _, handlers, dispose) = buildRouters();
    switch (await* handlers.repositoryHandler.createRecord(createRecordRequest)) {
      case (#ok(response)) { dispose(); #ok(CID.toText(response.cid)) };
      case (#err(e)) #err("Failed to post to the feed: " # e);
    };

  };

  public shared query func exportRepoData() : async Result.Result<Repository.ExportData, Text> {
    let (_, _, handlers, _) = buildRouters();
    let repository = handlers.repositoryHandler.get();
    Repository.exportData(repository, #full({ includeHistorical = true }));
  };

  // Candid API methods
  public shared ({ caller }) func initialize(request : PdsInterface.InitializeRequest) : async Result.Result<(), Text> {
    if (caller != owner and caller != deployer) {
      return #err("Only the owner or deployer can initialize the PDS");

    };
    let (_, _, handlers, dispose) = buildRouters();
    // TODO prevent re-initialization?
    let (plcIndentifier, repository) : (DID.Plc.DID, ?Repository.Repository) = switch (request.plc) {
      case (#new(createRequest)) {
        switch (await* handlers.didDirectoryHandler.create(createRequest)) {
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
          case (#ok(parsedFile)) switch (CarUtil.toRepository(parsedFile)) {
            case (#ok((did, repo))) (did, ?repo);
            case (#err(error)) return #err("Failed to build repository from CAR file: " # error);
          };
          case (#err(error)) return #err("Failed to parse CAR file: " # error);
        };
      };
    };
    handlers.serverInfoHandler.set({
      hostname = request.hostname;
      plcIdentifier = plcIndentifier;
      handlePrefix = request.handlePrefix;
    });
    switch (await* handlers.repositoryHandler.initialize(repository)) {
      case (#ok(_)) { dispose(); #ok };
      case (#err(e)) return #err("Failed to create repository: " # e);
    };
  };

};
