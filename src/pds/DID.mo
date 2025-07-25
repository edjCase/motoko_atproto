import Result "mo:base/Result";
import Blob "mo:base/Blob";
import Text "mo:base/Text";
import DagCbor "mo:dag-cbor";
import Sha256 "mo:sha2/Sha256";
import PlcDID "mo:did/Plc";
import DID "mo:did";
import BaseX "mo:base-x-encoder";
import TextX "mo:xtended-text/TextX";
import KeyHandler "Handlers/KeyHandler";
import Array "mo:new-base/Array";
import AtUri "./Types/AtUri";
import DIDDocument "Types/DIDDocument";
import Json "mo:json";
import Order "mo:new-base/Order";

module {

    public type BuildPlcRequest = {
        alsoKnownAs : [Text];
        services : [PlcService];
    };

    public type PlcRequestInfo = {
        request : SignedPlcRequest;
        did : DID.Plc.DID;
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
        signature : Blob;
    };

    public type PlcService = {
        name : Text;
        type_ : Text;
        endpoint : Text;
    };

    public func comparePlcDID(did1 : DID.Plc.DID, did2 : DID.Plc.DID) : Order.Order {
        if (did1 == did2) return #equal;
        Text.compare(did1.identifier, did2.identifier);
    };

    // Generate the AT Protocol DID Document
    public func generateDIDDocument(
        plcDid : PlcDID.DID,
        webDid : DID.Web.DID,
        verificationPublicKey : DID.Key.DID,
    ) : DIDDocument.DIDDocument {

        let webDidText : Text = DID.Web.toText(webDid);
        {
            id = #web(webDid);
            context = [
                "https://www.w3.org/ns/did/v1",
                "https://w3id.org/security/suites/secp256k1-2019/v1",
            ];
            alsoKnownAs = [
                AtUri.toText({
                    repoId = plcDid;
                    collectionAndRecord = null;
                })
            ];
            verificationMethod = [{
                id = webDidText # "#atproto";
                type_ = "Multikey";
                controller = #web(webDid);
                publicKeyMultibase = ?verificationPublicKey;
            }];
            authentication = [
                webDidText # "#atproto"
            ];
            assertionMethod = [
                webDidText # "#atproto"
            ];
        };
    };

    public func buildPlcRequest(
        request : BuildPlcRequest,
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
                    service.name,
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
