import DID "mo:did@2";
import Result "mo:core@1/Result";
import Json "mo:json@1";
import KeyHandler "./KeyHandler";
import DagCbor "mo:dag-cbor@2";
import IC "mo:ic@3/Call";
import Array "mo:core@1/Array";
import BaseX "mo:base-x-encoder@2";
import Sha256 "mo:sha2/Sha256";
import Error "mo:core@1/Error";
import TextX "mo:xtended-text@2/TextX";
import Text "mo:core@1/Text";
import Debug "mo:core@1/Debug";

module {

  public type CreatePlcRequest = {
    alsoKnownAs : [Text];
    services : [PlcService];
  };

  type PlcRequestInfo = {
    request : SignedPlcRequest;
    did : DID.Plc.DID;
  };

  type PlcRequest = {
    type_ : Text;
    rotationKeys : [Text];
    verificationMethods : [(Text, Text)];
    alsoKnownAs : [Text];
    services : [PlcService];
    prev : ?Text;
  };

  type SignedPlcRequest = PlcRequest and {
    signature : Blob;
  };

  public type PlcService = {
    id : Text;
    type_ : Text;
    endpoint : Text;
  };

  public class Handler(keyHandler : KeyHandler.Handler) {

    public func create(request : CreatePlcRequest) : async* Result.Result<DID.Plc.DID, Text> {

      let requestInfo = switch (
        await* buildPlcRequest(
          request,
          keyHandler,
        )
      ) {
        case (#ok(info)) info;
        case (#err(err)) return #err("Failed to build PLC request: " # err);
      };

      // Convert to JSON
      let json = requestToJson(requestInfo.request);

      let body : Blob = Text.encodeUtf8(Json.stringify(json, null));

      let httpRequest = {
        url = "https://plc.directory/" # DID.Plc.toText(requestInfo.did);
        method = #post;
        max_response_bytes = null;
        body = ?body;
        transform = null;
        headers = [{ name = "Content-Type"; value = "application/json" }];
        is_replicated = ?false;
      };
      let httpResponse = try {
        await IC.httpRequest(httpRequest);
      } catch (e) {
        return #err("PLC creation request failed: " # Error.message(e));
      };
      if (httpResponse.status != 200) {
        if (httpResponse.status == 400 and body == "{\"message\":\"Operations not correctly ordered\"}") {
          // Already created
          // TODO better way to do this?
          return #ok(requestInfo.did);
        };
        return #err("Failed to create PLC.\nResponse: " # debug_show (Text.decodeUtf8(httpResponse.body)) # "\nRequest: " # debug_show (Text.decodeUtf8(body)) # "\nDID: " # DID.Plc.toText(requestInfo.did));
      };

      #ok(requestInfo.did);
    };

  };

  public func requestToJson(request : SignedPlcRequest) : Json.Json {
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
          service.id,
          #object_([
            ("type", #string(service.type_)),
            ("endpoint", #string(service.endpoint)),
          ]),
        ),
      )
    );

    #object_([
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
      ("sig", #string(BaseX.toBase64(request.signature.vals(), #url({ includePadding = false })))),
    ]);
  };

  public func buildPlcRequest(
    request : CreatePlcRequest,
    keyHandler : KeyHandler.Handler,
  ) : async* Result.Result<PlcRequestInfo, Text> {

    let rotationPublicKeyDid = switch (await* keyHandler.getPublicKey(#rotation)) {
      case (#ok(did)) did;
      case (#err(err)) return #err("Failed to get rotation public key: " # err);
    };
    let verificationPublicKeyDid = switch (await* keyHandler.getPublicKey(#verification)) {
      case (#ok(did)) did;
      case (#err(err)) return #err("Failed to get verification public key: " # err);
    };
    // Build the request object
    let plcRequest : PlcRequest = {
      type_ = "plc_operation";
      rotationKeys = [DID.Key.toText(rotationPublicKeyDid, #base58btc)];
      verificationMethods = [("atproto", DID.Key.toText(verificationPublicKeyDid, #base58btc))];
      alsoKnownAs = request.alsoKnownAs;
      services = request.services;
      prev = null;
    };

    // Convert to CBOR and sign
    let requestCborMap = switch (requestToCborMap(plcRequest)) {
      case (#ok(cbor)) cbor;
      case (#err(err)) return #err(err);
    };

    let messageDagCborBytes : [Nat8] = switch (DagCbor.toBytes(#map(requestCborMap))) {
      case (#ok(blob)) blob;
      case (#err(err)) return #err("Failed to encode request to CBOR: " # debug_show (err));
    };

    let messageHash : Blob = Sha256.fromArray(#sha256, messageDagCborBytes);
    let signature = switch (await* keyHandler.sign(#rotation, messageHash)) {
      case (#ok(sig)) sig;
      case (#err(err)) return #err("Failed to sign message: " # err);
    };
    let signedPlcRequest : SignedPlcRequest = {
      plcRequest with
      signature = signature;
    };

    let signedCborMap = Array.concat(
      requestCborMap,
      [
        ("sig", #text(BaseX.toBase64(signature.vals(), #url({ includePadding = false })))),
      ],
    );

    let did = switch (generateDidFromCbor(#map(signedCborMap))) {
      case (#ok(did)) did;
      case (#err(err)) return #err("Failed to generate DID from signed request: " # err);
    };
    #ok({
      request = signedPlcRequest;
      did = did;
    });
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
          service.id,
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

  private func generateDidFromCbor(signedCbor : DagCbor.Value) : Result.Result<DID.Plc.DID, Text> {
    let signedDagCborBytes : [Nat8] = switch (DagCbor.toBytes(signedCbor)) {
      case (#ok(blob)) blob;
      case (#err(err)) return #err("Failed to encode signed request to CBOR: " # debug_show (err));
    };

    let hash = Sha256.fromArray(#sha256, signedDagCborBytes);
    let base32Hash = BaseX.toBase32(hash.vals(), #standard({ isUpper = false; includePadding = false }));
    #ok({
      identifier = TextX.slice(base32Hash, 0, 24);
    });
  };
};
