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
import RouteContext "mo:liminal/RouteContext";
import Debug "mo:new-base/Debug";
import DID "../did";
import RepositoryHandler "Handlers/RepositoryHandler";
import ServerInfoHandler "Handlers/ServerInfoHandler";
import ServerInfo "Types/ServerInfo";
import { ic } "mo:ic";
import Error "mo:new-base/Error";
import Cbor "mo:cbor";
import Array "mo:new-base/Array";

actor {

  let urls = HashMap.HashMap<Text, ()>(10, Text.equal, Text.hash);

  stable var repositoryStableData : RepositoryHandler.StableData = {
    repositories = [];
  };
  stable var serverInfoStableData : ServerInfoHandler.StableData = {
    info = null;
  };

  var repositoryHandler = RepositoryHandler.Handler(repositoryStableData);
  var serverInfoHandler = ServerInfoHandler.Handler(serverInfoStableData);

  system func preupgrade() {
    repositoryStableData := repositoryHandler.toStableData();
    serverInfoStableData := serverInfoHandler.toStableData();
  };

  system func postupgrade() {
    repositoryHandler := RepositoryHandler.Handler(repositoryStableData);
    serverInfoHandler := ServerInfoHandler.Handler(serverInfoStableData);
  };

  let xrpcRouter = XrpcRouter.Router(repositoryHandler, serverInfoHandler);
  let wellKnownRouter = WellKnownRouter.Router();

  public query func getUrls() : async [Text] {
    urls.keys() |> Iter.toArray(_);
  };

  private func loggingMiddleware() : App.Middleware {
    {
      handleQuery = func(context : Liminal.HttpContext, next : App.Next) : App.QueryResult {
        next();
      };
      handleUpdate = func(context : Liminal.HttpContext, next : App.NextAsync) : async* App.HttpResponse {
        Debug.print("Update request: " # context.request.url);
        urls.put(context.request.url, ());
        await* next();
      };
    };
  };

  let routerConfig : RouterMiddleware.Config = {
    prefix = null;
    identityRequirement = null;
    routes = [
      Router.getQuery("/xrpc/{nsid}", xrpcRouter.routeGet),
      Router.postUpdate("/xrpc/{nsid}", xrpcRouter.routePost),
      Router.getAsyncUpdate("/.well-known/did.json", wellKnownRouter.getDidDocument),
      Router.getQuery("/.well-known/ic-domains", wellKnownRouter.getIcDomains),
    ];
  };

  // Http App
  let app = Liminal.App({
    middleware = [
      loggingMiddleware(),
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
    logger = Liminal.debugLogger;
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

  public type PlcRequest = {
    type_ : Text;
    rotationKeys : [Text];
    verificationMethods : [(Text, Text)];
    alsoKnownAs : [Text];
    services : [PlcService];
    prev : ?Text;
  };

  public type SignedPlcRequest = PlcRequest and {
    sig : Blob;
  };

  public type PlcService = {
    type_ : Text;
    endpoint : Text;
  };

  public func buildPlcRequest() : async Result.Result<SignedPlcRequest, Text> {
    let rotationPublicKeyDid = switch (await* getPublicKeyDid("rotation_key_test")) {
      case (#ok(did)) did;
      case (#err(err)) return #err("Failed to get rotation public key: " # err);
    };
    let verificationPublicKeyDid = switch (await* getPublicKeyDid("verification_key_test")) {
      case (#ok(did)) did;
      case (#err(err)) return #err("Failed to get verification public key: " # err);
    };
    let request : PlcRequest = {
      type_ = "plc_operation";
      rotationKeys = [rotationPublicKeyDid];
      verificationMethods = [("atproto", verificationPublicKeyDid)];
      alsoKnownAs = ["at://edjcase.com"];
      services = [{
        type_ = "atproto_pds";
        endpoint = "https://edjcase.com";
      }];
      prev = null;
    };
    let rotationKeysCbor = request.rotationKeys
    |> Array.map<Text, Cbor.Value>(_, func(key : Text) : Cbor.Value = #majorType3(key));
    let verificationMethodsCbor = request.verificationMethods
    |> Array.map<(Text, Text), Cbor.Value>(
      _,
      func(pair : (Text, Text)) : Cbor.Value = #majorType5([
        (#majorType3("type"), #majorType3(pair.0)),
        (#majorType3("did"), #majorType3(pair.1)),
      ]),
    );
    let alsoKnownAsCbor = request.alsoKnownAs
    |> Array.map<Text, Cbor.Value>(_, func(aka : Text) : Cbor.Value = #majorType3(aka));
    let servicesCbor = request.services
    |> Array.map<PlcService, Cbor.Value>(
      _,
      func(service : PlcService) : Cbor.Value = #majorType5([
        (#majorType3("type"), #majorType3(service.type_)),
        (#majorType3("endpoint"), #majorType3(service.endpoint)),
      ]),
    );

    let prevCbor : Cbor.Value = switch (request.prev) {
      case (?prev) #majorType3(prev);
      case (null) #majorType7(#_null);
    };

    let requestCbor : Cbor.Value = #majorType5([
      (#majorType3("type"), #majorType3(request.type_)),
      (#majorType3("rotationKeys"), #majorType4(rotationKeysCbor)),
      (#majorType3("verificationMethods"), #majorType4(verificationMethodsCbor)),
      (#majorType3("alsoKnownAs"), #majorType4(alsoKnownAsCbor)),
      (#majorType3("services"), #majorType4(servicesCbor)),
      (#majorType3("prev"), prevCbor),
    ]);
    let messageCbor : [Nat8] = switch (Cbor.encode(requestCbor)) {
      case (#ok(blob)) blob;
      case (#err(err)) return #err("Failed to encode request to CBOR: " # debug_show (err));
    };
    let messageHash : Blob = "";
    let signature : Blob = "";
    #ok({
      request with
      sig = signature;
    });

  };

  private func getPublicKeyDid(name : Text) : async* Result.Result<Text, Text> {
    try {
      let { public_key } = await ic.ecdsa_public_key({
        canister_id = null;
        derivation_path = [];
        key_id = {
          curve = #secp256k1;
          name = name;
        };
      });
      #ok("did:key:" # debug_show (public_key));
    } catch (e) {
      #err("Failed to get public key: " # Error.message(e));
    };
  };

};
