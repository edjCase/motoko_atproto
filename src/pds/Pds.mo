import Text "mo:core@1/Text";
import Result "mo:core@1/Result";
import XrpcRouter "./XrpcRouter";
import WellKnownRouter "./WellKnownRouter";
import HtmlRouter "./HtmlRouter";
import RouterMiddleware "mo:liminal@3/Middleware/Router";
import CompressionMiddleware "mo:liminal@3/Middleware/Compression";
import CORSMiddleware "mo:liminal@3/Middleware/CORS";
import Liminal "mo:liminal@3";
import Router "mo:liminal@3/Router";
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
import CertifiedAssets "mo:certified-assets@0";
import StableCertifiedAssets "mo:certified-assets@0/Stable";
import App "mo:liminal@3/App";
import IcWebSocketCdk "mo:ic-websocket-cdk@0";
import IcWebSocketCdkState "mo:ic-websocket-cdk@0/State";
import IcWebSocketCdkTypes "mo:ic-websocket-cdk@0/Types";

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
  var certStore = CertifiedAssets.init_stable_store();

  transient let tidGenerator = TID.Generator();

  // Handlers
  transient let keyHandler = KeyHandler.Handler(keyHandlerStableData);
  transient let serverInfoHandler = ServerInfoHandler.Handler(serverInfoStableData);
  transient let didDirectoryHandler = DIDDirectoryHandler.Handler(keyHandler);
  transient let repositoryHandler = RepositoryHandler.Handler(
    repositoryStableData,
    keyHandler,
    serverInfoHandler,
    tidGenerator,
  );

  // Routers
  transient let xrpcRouter = XrpcRouter.Router(
    repositoryHandler,
    serverInfoHandler,
    keyHandler,
  );
  transient let wellKnownRouter = WellKnownRouter.Router(
    serverInfoHandler,
    keyHandler,
    certStore,
  );
  transient let htmlRouter = HtmlRouter.Router(
    serverInfoHandler
  );

  func buildLoggingMiddleware() : App.Middleware {
    {
      name = "Logging";
      handleQuery = func(httpContext : Liminal.HttpContext, next : App.Next) : App.QueryResult {
        next();
      };
      handleUpdate = func(httpContext : Liminal.HttpContext, next : App.NextAsync) : async* App.HttpResponse {
        httpContext.log(#info, "Received HTTP update request: " # debug_show (httpContext.request));
        let response = await* next();
        httpContext.log(#info, "Responding to HTTP update request. Status Code: " # debug_show (response.statusCode) # ", Headers: " # debug_show (response.headers));
        response;
      };
    };
  };

  // Http App
  transient let routerConfig = {
    prefix = null;
    identityRequirement = null;
    routes = [
      Router.get("/xrpc/{nsid}", #upgradableQuery({ queryHandler = xrpcRouter.routeQuery; updateHandler = #async_(xrpcRouter.routeUpdateAsync) })),
      Router.post("/xrpc/{nsid}", #upgradableQuery({ queryHandler = xrpcRouter.routeQuery; updateHandler = #async_(xrpcRouter.routeUpdateAsync) })),
      Router.get("/.well-known/did.json", #update(#async_(wellKnownRouter.getDidDocument))),
      Router.get("/.well-known/ic-domains", #query_(wellKnownRouter.getIcDomains)),
      Router.get("/.well-known/atproto-did", #update(#sync(wellKnownRouter.getAtprotoDid))),
      Router.get("/", #update(#sync(htmlRouter.getLandingPage))),
    ];
  };
  transient let app = Liminal.App({
    middleware = [
      buildLoggingMiddleware(),
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
    urlNormalization = {
      pathIsCaseSensitive = false;
      preserveTrailingSlash = false;
      queryKeysAreCaseSensitive = false;
      removeEmptyPathSegments = true;
      resolvePathDotSegments = true;
      usernameIsCaseSensitive = false;
    };
  });

  system func preupgrade() {
    keyHandlerStableData := keyHandler.toStableData();
    serverInfoStableData := serverInfoHandler.toStableData();
    repositoryStableData := repositoryHandler.toStableData();
  };

  transient let params = IcWebSocketCdkTypes.WsInitParams(null, null);
  transient let ws_state = IcWebSocketCdkState.IcWebSocketState(params);

  transient let handlers = IcWebSocketCdkTypes.WsHandlers(
    ?webSocketRouter.onOpen,
    ?webSocketRouter.onMessage,
    ?webSocketRouter.onClose,
  );

  let ws = IcWebSocketCdk.IcWebSocket(ws_state, params, handlers);

  // Http server methods
  public query func http_request(request : Liminal.RawQueryHttpRequest) : async Liminal.RawQueryHttpResponse {
    app.http_request(request);
  };

  public func http_request_update(request : Liminal.RawUpdateHttpRequest) : async Liminal.RawUpdateHttpResponse {
    await* app.http_request_update(request);
  };

  // Webscoket server methods

  // method called by the WS Gateway after receiving FirstMessage from the client
  public shared ({ caller }) func ws_open(args : IcWebSocketCdk.CanisterWsOpenArguments) : async IcWebSocketCdk.CanisterWsOpenResult {
    await ws.ws_open(caller, args);
  };

  // method called by the Ws Gateway when closing the IcWebSocket connection
  public shared ({ caller }) func ws_close(args : IcWebSocketCdk.CanisterWsCloseArguments) : async IcWebSocketCdk.CanisterWsCloseResult {
    await ws.ws_close(caller, args);
  };

  // method called by the frontend SDK to send a message to the canister
  public shared ({ caller }) func ws_message(args : IcWebSocketCdk.CanisterWsMessageArguments, msg : ?AppMessage) : async IcWebSocketCdk.CanisterWsMessageResult {
    await ws.ws_message(caller, args, msg);
  };

  // method called by the WS Gateway to get messages for all the clients it serves
  public shared query ({ caller }) func ws_get_messages(args : IcWebSocketCdk.CanisterWsGetMessagesArguments) : async IcWebSocketCdk.CanisterWsGetMessagesResult {
    ws.ws_get_messages(caller, args);
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
    switch (await* repositoryHandler.createRecord(createRecordRequest)) {
      case (#ok(response)) #ok(CID.toText(response.cid));
      case (#err(e)) #err("Failed to post to the feed: " # e);
    };
  };

  public shared query func exportRepoData() : async Result.Result<Repository.ExportData, Text> {
    let repository = repositoryHandler.get();
    Repository.exportData(repository, #full({ includeHistorical = true }));
  };

  // Candid API methods
  public shared ({ caller }) func initialize(request : PdsInterface.InitializeRequest) : async Result.Result<(), Text> {
    if (caller != owner and caller != deployer) {
      return #err("Only the owner or deployer can initialize the PDS");
    };
    // TODO prevent re-initialization?
    let (plcIndentifier, repository) : (DID.Plc.DID, ?Repository.Repository) = switch (request.plc) {
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
          case (#ok(parsedFile)) switch (CarUtil.toRepository(parsedFile)) {
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
      serviceSubdomain = request.serviceSubdomain;
    });
    switch (await* repositoryHandler.initialize(repository)) {
      case (#ok(_)) ();
      case (#err(e)) return #err("Failed to create repository: " # e);
    };

    // TODO can this be built into the WellKnownRouter instead?
    let serverInfo = serverInfoHandler.get();
    let icDomains = WellKnownRouter.getIcDomainsText(serverInfo);
    let icDomainsBlob = Text.encodeUtf8(icDomains);
    let icDomainsEndpoint = CertifiedAssets.Endpoint("/.well-known/ic-domains", ?icDomainsBlob).no_certification().no_request_certification();
    StableCertifiedAssets.certify(certStore, icDomainsEndpoint);
    #ok;
  };

  public shared ({ caller }) func createPlcDid(request : PdsInterface.CreatePlcRequest) : async Result.Result<Text, Text> {
    if (caller != owner and caller != deployer) {
      return #err("Only the owner or deployer can update the PLC identifier");
    };
    switch (await* didDirectoryHandler.create(request)) {
      case (#ok(did)) #ok(DID.Plc.toText(did));
      case (#err(e)) #err("Failed to create PLC identifier: " # e);
    };
  };

  public shared ({ caller }) func updatePlcDid(request : PdsInterface.UpdatePlcRequest) : async Result.Result<(), Text> {
    if (caller != owner and caller != deployer) {
      return #err("Only the owner or deployer can update the PLC identifier");
    };
    let did = switch (DID.Plc.fromText(request.did)) {
      case (#ok(did)) did;
      case (#err(e)) return #err("Invalid PLC identifier '" # request.did # "': " # e);
    };
    let updateRequest = {
      request with
      did = did;
    };
    switch (await* didDirectoryHandler.update(updateRequest)) {
      case (#ok) #ok;
      case (#err(e)) #err("Failed to update PLC identifier: " # e);
    };
  };

};
