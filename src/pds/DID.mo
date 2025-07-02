import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Blob "mo:base/Blob";
import Text "mo:base/Text";
import DagCbor "mo:dag-cbor";
import KeyDID "mo:did/Key";
import Array "mo:new-base/Array";
import Sha256 "mo:sha2/Sha256";
import ServerInfo "./Types/ServerInfo";
import PlcDID "mo:did/Plc";
import WebDID "mo:did/Web";
import DID "mo:did";
import KeyHandler "./Handlers/KeyHandler";

module {

    public type BuildPlcRequest = {
        alsoKnownAs : [Text];
        services : [PlcService];
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

    public type DidDocument = {
        id : DID.DID;
        context : [Text];
        alsoKnownAs : [Text];
        verificationMethod : [VerificationMethod];
        authentication : [Text];
        assertionMethod : [Text];
    };

    public type VerificationMethod = {
        id : Text;
        type_ : Text;
        controller : DID.DID;
        publicKeyMultibase : ?KeyDID.DID;
    };

    // Generate the AT Protocol DID Document
    public func generateDIDDocument(
        plcDid : PlcDID.DID,
        webDid : WebDID.DID,
        verificationPublicKey : KeyDID.DID,
    ) : DidDocument {

        let webDidText : Text = WebDID.toText(webDid);
        let plcDidText : Text = PlcDID.toText(plcDid);
        {
            id = #web(webDid);
            context = [
                "https://www.w3.org/ns/did/v1",
                "https://w3id.org/security/suites/secp256k1-2019/v1",
            ];
            alsoKnownAs = [
                "at://" # plcDidText
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

    public func buildPlcRequest(request : BuildPlcRequest, keyHandler : KeyHandler.Handler) : async* Result.Result<SignedPlcRequest, Text> {

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
            rotationKeys = [KeyDID.toText(rotationPublicKeyDid, #base58btc)];
            verificationMethods = [("atproto", KeyDID.toText(verificationPublicKeyDid, #base58btc))];
            alsoKnownAs = request.alsoKnownAs;
            services = request.services;
            prev = null;
        };

        // Convert to CBOR and sign
        let requestCborMap = switch (requestToCborMap(plcRequest)) {
            case (#ok(cbor)) cbor;
            case (#err(err)) return #err(err);
        };

        let messageDagCborBytes : [Nat8] = switch (DagCbor.encode(#map(requestCborMap))) {
            case (#ok(blob)) blob;
            case (#err(err)) return #err("Failed to encode request to CBOR: " # debug_show (err));
        };

        let messageHash : Blob = Sha256.fromArray(#sha256, messageDagCborBytes);
        let signature = switch (await* keyHandler.sign(#rotation, messageHash)) {
            case (#ok(sig)) sig;
            case (#err(err)) return #err("Failed to sign message: " # err);
        };
        #ok({
            plcRequest with
            sig = signature;
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

};
