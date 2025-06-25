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
import Blob "mo:new-base/Blob";
import Sha256 "mo:sha2/Sha256";
import KeyDID "mo:did/Key";
import Json "mo:json";
import BaseX "mo:base-x-encoder";
import TextX "mo:xtended-text/TextX";

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
    name : Text;
    type_ : Text;
    endpoint : Text;
  };
  public func buildPlcRequest() : async Result.Result<(Text, Text), Text> {
    let rotationKeyId : [Blob] = [];
    let verificationKeyId : [Blob] = ["\00"];

    // Get public keys
    let rotationPublicKeyDid = switch (await* getPublicKeyDid(rotationKeyId)) {
      case (#ok(did)) did;
      case (#err(err)) return #err("Failed to get rotation public key: " # err);
    };
    let verificationPublicKeyDid = switch (await* getPublicKeyDid(verificationKeyId)) {
      case (#ok(did)) did;
      case (#err(err)) return #err("Failed to get verification public key: " # err);
    };

    // Build the request object
    let request : PlcRequest = {
      type_ = "plc_operation";
      rotationKeys = [KeyDID.toText(rotationPublicKeyDid, #base58btc)];
      verificationMethods = [("atproto", KeyDID.toText(verificationPublicKeyDid, #base58btc))];
      alsoKnownAs = ["at://edjcase.com"];
      services = [{
        name = "atproto_pds";
        type_ = "AtprotoPersonalDataServer";
        endpoint = "https://edjcase.com";
      }];
      prev = null;
    };

    // Convert to CBOR and sign
    let requestCborMap = switch (requestToCborMap(request)) {
      case (#ok(cbor)) cbor;
      case (#err(err)) return #err(err);
    };

    let messageDagCborBytes : [Nat8] = switch (DagCbor.encode(#map(requestCborMap))) {
      case (#ok(blob)) blob;
      case (#err(err)) return #err("Failed to encode request to CBOR: " # debug_show (err));
    };

    let messageHash : Blob = Sha256.fromArray(#sha256, messageDagCborBytes);
    let signature = switch (await* sign(rotationKeyId, messageHash)) {
      case (#ok(sig)) sig;
      case (#err(err)) return #err("Failed to sign message: " # err);
    };
    let signatureText = BaseX.toBase64(signature.vals(), #url({ includePadding = false }));

    // Create signed operation and generate DID
    let signedCborMap = Array.concat(
      requestCborMap,
      [("sig", #text(signatureText))],
    );

    let did = switch (generateDidFromCbor(#map(signedCborMap))) {
      case (#ok(did)) did;
      case (#err(err)) return #err(err);
    };

    // Convert to JSON
    let json = requestToJson(request, signatureText);

    #ok((did, json));
  };

  private func requestToCborMap(request : PlcRequest) : Result.Result<[(Text, DagCbor.Value)], Text> {
    let rotationKeysCbor = request.rotationKeys
    |> Array.map<Text, DagCbor.Value>(_, func(key : Text) : DagCbor.Value = #text(key));

    let verificationMethodsCbor = #map(
      request.verificationMethods
      |> Array.map<(Text, Text), (Text, DagCbor.Value)>(
        _,
        func(pair : (Text, Text)) : (Text, DagCbor.Value) = (pair.0, #text(pair.1)),
      )
    );

    let alsoKnownAsCbor = request.alsoKnownAs
    |> Array.map<Text, DagCbor.Value>(_, func(aka : Text) : DagCbor.Value = #text(aka));

    let servicesCbor : DagCbor.Value = #map(
      request.services
      |> Array.map<PlcService, (Text, DagCbor.Value)>(
        _,
        func(service : PlcService) : (Text, DagCbor.Value) = (
          service.name,
          #map([
            ("type", #text(service.type_)),
            ("endpoint", #text(service.endpoint)),
          ]),
        ),
      )
    );

    let prevCbor : DagCbor.Value = switch (request.prev) {
      case (?prev) #text(prev);
      case (null) #null_;
    };

    #ok([
      ("type", #text(request.type_)),
      ("rotationKeys", #array(rotationKeysCbor)),
      ("verificationMethods", verificationMethodsCbor),
      ("alsoKnownAs", #array(alsoKnownAsCbor)),
      ("services", servicesCbor),
      ("prev", prevCbor),
    ]);
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

  private func requestToJson(request : PlcRequest, signature : Text) : Text {
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
