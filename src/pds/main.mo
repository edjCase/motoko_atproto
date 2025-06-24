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
import { ic } "mo:ic";
import Error "mo:new-base/Error";
import DagCbor "mo:dag-cbor";
import Array "mo:new-base/Array";
import Sha256 "mo:sha2/Sha256";
import KeyDID "mo:did/Key";

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
    let rotationKeyId : [Blob] = [];
    let verificationKeyId : [Blob] = ["\00"];
    let rotationPublicKeyDid = switch (await* getPublicKeyDid(rotationKeyId)) {
      case (#ok(did)) did;
      case (#err(err)) return #err("Failed to get rotation public key: " # err);
    };
    let verificationPublicKeyDid = switch (await* getPublicKeyDid(verificationKeyId)) {
      case (#ok(did)) did;
      case (#err(err)) return #err("Failed to get verification public key: " # err);
    };
    let request : PlcRequest = {
      type_ = "plc_operation";
      rotationKeys = [KeyDID.toText(rotationPublicKeyDid, #base58btc)];
      verificationMethods = [("atproto", KeyDID.toText(verificationPublicKeyDid, #base58btc))];
      alsoKnownAs = ["at://edjcase.com"];
      services = [{
        type_ = "atproto_pds";
        endpoint = "https://edjcase.com";
      }];
      prev = null;
    };
    let rotationKeysCbor = request.rotationKeys
    |> Array.map<Text, DagCbor.Value>(_, func(key : Text) : DagCbor.Value = #text(key));
    let verificationMethodsCbor = request.verificationMethods
    |> Array.map<(Text, Text), DagCbor.Value>(
      _,
      func(pair : (Text, Text)) : DagCbor.Value = #map([
        ("type", #text(pair.0)),
        ("did", #text(pair.1)),
      ]),
    );
    let alsoKnownAsCbor = request.alsoKnownAs
    |> Array.map<Text, DagCbor.Value>(_, func(aka : Text) : DagCbor.Value = #text(aka));
    let servicesCbor = request.services
    |> Array.map<PlcService, DagCbor.Value>(
      _,
      func(service : PlcService) : DagCbor.Value = #map([
        ("type", #text(service.type_)),
        ("endpoint", #text(service.endpoint)),
      ]),
    );

    let prevCbor : DagCbor.Value = switch (request.prev) {
      case (?prev) #text(prev);
      case (null) #null_;
    };

    let requestCbor : DagCbor.Value = #map([
      ("type", #text(request.type_)),
      ("rotationKeys", #array(rotationKeysCbor)),
      ("verificationMethods", #array(verificationMethodsCbor)),
      ("alsoKnownAs", #array(alsoKnownAsCbor)),
      ("services", #array(servicesCbor)),
      ("prev", prevCbor),
    ]);
    let messageDagCborBytes : [Nat8] = switch (DagCbor.encode(requestCbor)) {
      case (#ok(blob)) blob;
      case (#err(err)) return #err("Failed to encode request to CBOR: " # debug_show (err));
    };
    let messageHash : Blob = Sha256.fromArray(#sha256, messageDagCborBytes);
    switch (await* sign(rotationKeyId, messageHash)) {
      case (#ok(sig)) #ok({
        request with
        sig = sig;
      });
      case (#err(err)) return #err("Failed to sign message: " # err);
    };

  };

  private func sign(derivationPath : [Blob], messageHash : Blob) : async* Result.Result<Blob, Text> {
    try {
      let { signature } = await (with cycles = 26_153_846_153) ic.sign_with_ecdsa({
        derivation_path = derivationPath;
        key_id = {
          curve = #secp256k1;
          name = "dfx_test_key"; // TODO based on environment
        };
        message_hash = messageHash;
      });
      #ok(signature);
    } catch (e) {
      #err("Failed to sign message: " # Error.message(e));
    };
  };

  private func getPublicKeyDid(derivationPath : [Blob]) : async* Result.Result<KeyDID.DID, Text> {
    try {
      let { public_key } = await ic.ecdsa_public_key({
        canister_id = null;
        derivation_path = derivationPath;
        key_id = {
          curve = #secp256k1;
          name = "dfx_test_key"; // TODO based on environment
        };
      });
      #ok({
        keyType = #secp256k1;
        publicKey = public_key;
      });
    } catch (e) {
      #err("Failed to get public key: " # Error.message(e));
    };
  };

};
