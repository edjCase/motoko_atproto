import Text "mo:base/Text";
import Result "mo:base/Result";
import XrpcRouter "./XrpcRouter";
import WellKnownRouter "./WellKnownRouter";
import RouterMiddleware "mo:liminal@1/Middleware/Router";
import CompressionMiddleware "mo:liminal@1/Middleware/Compression";
import CORSMiddleware "mo:liminal@1/Middleware/CORS";
import JWTMiddleware "mo:liminal@1/Middleware/JWT";
import Liminal "mo:liminal@1";
import Router "mo:liminal@1/Router";
import RepositoryHandler "Handlers/RepositoryHandler";
import ServerInfoHandler "Handlers/ServerInfoHandler";
import KeyHandler "Handlers/KeyHandler";
import AccountHandler "Handlers/AccountHandler";
import DIDDirectoryHandler "Handlers/DIDDirectoryHandler";
import ServerInfo "Types/ServerInfo";
import DIDModule "./DID";
import DID "mo:did@2";
import TID "mo:tid@1";
import CID "mo:cid@1";
import PureMap "mo:core@1/pure/Map";
import Json "mo:json@1";
import UploadBlob "Types/Lexicons/Com/Atproto/Repo/UploadBlob";
import CreateAccount "Types/Lexicons/Com/Atproto/Server/CreateAccount";
import HttpContext "mo:liminal@1/HttpContext";
import App "mo:liminal@1/App";
import Runtime "mo:core@1/Runtime";

actor {
  transient let tidGenerator = TID.Generator();

  stable var repositoryStableData : RepositoryHandler.StableData = {
    repositories = PureMap.empty<DID.Plc.DID, RepositoryHandler.RepositoryWithData>();
    blobs = PureMap.empty<CID.CID, RepositoryHandler.BlobWithMetaData>();
  };
  stable var serverInfoStableData : ServerInfoHandler.StableData = {
    info = null;
  };
  stable var keyHandlerStableData : KeyHandler.StableData = {
    verificationDerivationPath = ["\00"]; // TODO: configure properly
  };
  stable var accountStableData : AccountHandler.StableData = {
    accounts = PureMap.empty<DID.Plc.DID, AccountHandler.AccountData>();
    sessions = PureMap.empty<Text, AccountHandler.Session>();
  };

  transient var keyHandler = KeyHandler.Handler(keyHandlerStableData);
  transient var didDirectoryHandler = DIDDirectoryHandler.Handler(keyHandler);
  transient var serverInfoHandler = ServerInfoHandler.Handler(serverInfoStableData);
  transient var repositoryHandler = RepositoryHandler.Handler(repositoryStableData, keyHandler, tidGenerator, serverInfoHandler);
  transient var accountHandler = AccountHandler.Handler(accountStableData, keyHandler, serverInfoHandler, didDirectoryHandler);
  transient var xrpcRouter = XrpcRouter.Router(repositoryHandler, serverInfoHandler, accountHandler);
  transient var wellKnownRouter = WellKnownRouter.Router(serverInfoHandler, keyHandler);

  system func preupgrade() {
    keyHandlerStableData := keyHandler.toStableData();
    serverInfoStableData := serverInfoHandler.toStableData();
    repositoryStableData := repositoryHandler.toStableData();
    accountStableData := accountHandler.toStableData();
  };

  system func postupgrade() {
    keyHandler := KeyHandler.Handler(keyHandlerStableData);
    didDirectoryHandler := DIDDirectoryHandler.Handler(keyHandler);
    serverInfoHandler := ServerInfoHandler.Handler(serverInfoStableData);
    repositoryHandler := RepositoryHandler.Handler(repositoryStableData, keyHandler, tidGenerator, serverInfoHandler);
    accountHandler := AccountHandler.Handler(accountStableData, keyHandler, serverInfoHandler, didDirectoryHandler);
    xrpcRouter := XrpcRouter.Router(repositoryHandler, serverInfoHandler, accountHandler);
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
      JWTMiddleware.new({
        locations = JWTMiddleware.defaultLocations;
        validation = {
          audience = #skip;
          issuer = #skip;
          signature = #skip;
          notBefore = false;
          expiration = false;
        };
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
  public func initialize(serverInfo : ServerInfo.ServerInfo) : async Result.Result<(), Text> {
    if (serverInfoHandler.get() != null) {
      return #err("Server is already initialized");
    };

    switch (await* repositoryHandler.create(serverInfo.plcDid)) {
      case (#ok(_)) ();
      case (#err(e)) return #err("Failed to create repository: " # e);
    };
    serverInfoHandler.set(serverInfo);
    #ok;
  };

  public query func isInitialized() : async Bool {
    serverInfoHandler.get() != null;
  };

  public func buildPlcRequest(request : DIDDirectoryHandler.CreatePlcRequest) : async Result.Result<(Text, Text), Text> {
    let requestInfo = switch (
      await* DIDDirectoryHandler.buildPlcRequest(
        request,
        keyHandler,
      )
    ) {
      case (#ok(info)) info;
      case (#err(err)) return #err("Failed to build PLC request: " # err);
    };

    // Convert to JSON
    let json = DIDDirectoryHandler.requestToJson(requestInfo.request);
    #ok((DID.Plc.toText(requestInfo.did), Json.stringify(json, null)));
  };

  public func uploadBlob(request : UploadBlob.Request) : async Result.Result<UploadBlob.Response, Text> {
    repositoryHandler.uploadBlob(request);
  };

  public func createAccount(request : CreateAccount.Request) : async Result.Result<CreateAccount.Response, Text> {
    await* accountHandler.create(request);
  };
};
