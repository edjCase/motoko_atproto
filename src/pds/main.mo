import Text "mo:base/Text";
import Iter "mo:base/Iter";
import HashMap "mo:base/HashMap";
import Result "mo:base/Result";
import XrpcRouter "./XrpcRouter";
import WellKnownRouter "./WellKnownRouter";
import RouterMiddleware "mo:liminal/Middleware/Router";
import CompressionMiddleware "mo:liminal/Middleware/Compression";
import CORSMiddleware "mo:liminal/Middleware/CORS";
import JWTMiddleware "mo:liminal/Middleware/JWT";
import Liminal "mo:liminal";
import App "mo:liminal/App";
import Router "mo:liminal/Router";
import Debug "mo:new-base/Debug";
import RepositoryHandler "Handlers/RepositoryHandler";
import ServerInfoHandler "Handlers/ServerInfoHandler";
import ServerInfo "Types/ServerInfo";
import Error "mo:new-base/Error";
import Array "mo:new-base/Array";
import Blob "mo:new-base/Blob";
import Sha256 "mo:sha2/Sha256";
import Json "mo:json";
import BaseX "mo:base-x-encoder";
import TextX "mo:xtended-text/TextX";

actor {

  stable var repositoryStableData : RepositoryHandler.StableData = {
    repositories = [];
  };
  stable var serverInfoStableData : ServerInfoHandler.StableData = {
    info = null;
  };
  stable var keyHandlerStableData : KeyHandler.StableData = {
    verificationDerivationPath = ["\00"]; // TODO
  };

  var repositoryHandler = RepositoryHandler.Handler(repositoryStableData);
  var serverInfoHandler = ServerInfoHandler.Handler(serverInfoStableData);
  var keyHandler = KeyHandler.Handler(keyHandlerStableData);

  system func preupgrade() {
    repositoryStableData := repositoryHandler.toStableData();
    serverInfoStableData := serverInfoHandler.toStableData();
    keyHandlerStableData := keyHandler.toStableData();
  };

  system func postupgrade() {
    repositoryHandler := RepositoryHandler.Handler(repositoryStableData);
    serverInfoHandler := ServerInfoHandler.Handler(serverInfoStableData);
    keyHandler := KeyHandler.Handler(keyHandlerStableData);
  };

  let xrpcRouter = XrpcRouter.Router(repositoryHandler, serverInfoHandler);
  let wellKnownRouter = WellKnownRouter.Router();

  let routerConfig : RouterMiddleware.Config = {
    prefix = null;
    identityRequirement = null;
    routes = [
      Router.getUpdate("/xrpc/{nsid}", xrpcRouter.routeGet),
      Router.postUpdate("/xrpc/{nsid}", xrpcRouter.routePost),
      Router.getAsyncUpdate("/.well-known/did.json", wellKnownRouter.getDidDocument),
      Router.getUpdate("/.well-known/ic-domains", wellKnownRouter.getIcDomains),
    ];
  };

  // Http App
  let app = Liminal.App({
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
      // RequireAuthMiddleware.new(#authenticated),
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

  public func initialize(serverInfo : ServerInfo.ServerInfo) : async Result.Result<(), Text> {
    serverInfoHandler.set(serverInfo);
    #ok;
  };

  public func isInitialized() : async Bool {
    false; // TODO
  };

  public func buildPlcRequest(request : BuildPlcRequest) : async Result.Result<(Text, Text), Text> {

    let signedPlcRequest = DID.buildPlcRequest(
      request,
      keyHandler,
    );

    let did = switch (generateDidFromCbor(signedPlcRequest)) {
      case (#ok(did)) did;
      case (#err(err)) return #err("Failed to generate DID from signed request: " # err);
    };

    // Convert to JSON
    let json = requestToJson(signedPlcRequest);

    #ok((did, json));
  };

  private func generateDidFromCbor(signedCbor : DagCbor.Value) : Result.Result<Text, Text> {
    let signedDagCborBytes : [Nat8] = switch (DagCbor.encode(signedCbor)) {
      case (#ok(blob)) blob;
      case (#err(err)) return #err("Failed to encode signed request to CBOR: " # debug_show (err));
    };

    let hash = Sha256.fromArray(#sha256, signedDagCborBytes);
    let base32Hash = BaseX.toBase32(hash.vals(), #standard({ isUpper = false; includePadding = false }));
    let did = "did:plc:" # TextX.slice(base32Hash, 0, 24);
    #ok(did);
  };

  private func requestToJson(request : SignedPlcRequest) : Text {
    func toTextArray(arr : [Text]) : [Json.Json] {
      arr |> Array.map(_, func(item : Text) : Json.Json = #string(item));
    };

    let verificationMethodsJsonObj : Json.Json = #object_(
      request.verificationMethods
      |> Array.map<(Text, Text), (Text, Json.Json)>(
        _,
        func(pair : (Text, Text)) : (Text, Json.Json) = (pair.0, #string(pair.1)),
      )
    );

    let servicesJsonObj : Json.Json = #object_(
      request.services
      |> Array.map<PlcService, (Text, Json.Json)>(
        _,
        func(service : PlcService) : (Text, Json.Json) = (
          service.name,
          #object_([
            ("type", #string(service.type_)),
            ("endpoint", #string(service.endpoint)),
          ]),
        ),
      )
    );

    let jsonObj : Json.Json = #object_([
      ("type", #string(request.type_)),
      ("rotationKeys", #array(request.rotationKeys |> toTextArray(_))),
      ("verificationMethods", verificationMethodsJsonObj),
      ("alsoKnownAs", #array(request.alsoKnownAs |> toTextArray(_))),
      ("services", servicesJsonObj),
      (
        "prev",
        switch (request.prev) {
          case (?prev) #string(prev);
          case (null) #null_;
        },
      ),
      ("sig", #string(signature)),
    ]);

    Json.stringify(jsonObj, null);
  };

};
