import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Error "mo:base/Error";
import Blob "mo:base/Blob";
import Text "mo:base/Text";
import Buffer "mo:base/Buffer";
import IC "mo:ic";
import { Base64 = Base64Engine; V2 } "mo:base64";

module {
    let ic = actor ("aaaaa-aa") : IC.Service;

    // Helper to convert public key blob to JWK format string
    private func publicKeyToJWK(publicKey : Blob) : Text {
        let base64EncodedKey : Text = Base64Engine(#v(V2), ?false).encode(#bytes(Blob.toArray(publicKey)));
        "{" #
        "\"kty\":\"EC\"," #
        "\"crv\":\"secp256k1\"," #
        "\"x\":\"" # base64EncodedKey # "\"" #
        "}";
    };

    // Generate the AT Protocol DID Document
    public func generateDIDDocument(domain : Text, userId : ?Principal) : async* Result.Result<Text, Text> {
        try {
            // Root key for DID operations and authentication
            let rootKey = switch (await* getEcdsaPublicKey(userId, ?"root")) {
                case (#ok(rootKey)) rootKey;
                case (#err(e)) return #err(e);
            };
            // Signing key for repository operations
            let signingKey = switch (await* getEcdsaPublicKey(userId, ?"signing")) {
                case (#ok(signingKey)) signingKey;
                case (#err(e)) return #err(e);
            };
            let did = "did:web:" # domain;

            let doc = "{" #
            "\"@context\":[" #
            "\"https://www.w3.org/ns/did/v1\"," #
            "\"https://w3id.org/security/suites/secp256k1-2019/v1\"" #
            "]," #
            "\"id\":\"" # did # "\"," #
            "\"verificationMethod\":[" #
            "{" #
            "\"id\":\"" # did # "#atproto\"," #
            "\"type\":\"EcdsaSecp256k1VerificationKey2019\"," #
            "\"controller\":\"" # did # "\"," #
            "\"publicKeyJwk\":" # publicKeyToJWK(rootKey) #
            "}," #
            "{" #
            "\"id\":\"" # did # "#atproto-repo\"," #
            "\"type\":\"EcdsaSecp256k1VerificationKey2019\"," #
            "\"controller\":\"" # did # "\"," #
            "\"publicKeyJwk\":" # publicKeyToJWK(signingKey) #
            "}" #
            "]," #
            "\"authentication\":[" #
            "\"" # did # "#atproto\"" #
            "]," #
            "\"assertionMethod\":[" #
            "\"" # did # "#atproto-repo\"" #
            "]" #
            "}";

            #ok(doc);
        } catch (e) {
            #err("Failed to generate DID document: " # Error.message(e));
        };
    };

    public func getEcdsaPublicKey(userId : ?Principal, derivedId : ?Text) : async* Result.Result<Blob, Text> {
        let { derivationPath; keyId } = getDerivationPath(userId, derivedId);

        try {
            let { public_key } = await ic.ecdsa_public_key({
                canister_id = null;
                derivation_path = derivationPath;
                key_id = keyId;
            });

            #ok(public_key);
        } catch (e) {
            #err("Failed to get public key: " # Error.message(e));
        };
    };

    public func signMessage(messageHash : Blob, userId : ?Principal, derivedId : ?Text) : async* Result.Result<Blob, Text> {
        let { derivationPath; keyId } = getDerivationPath(userId, derivedId);

        try {
            let { signature } = await ic.sign_with_ecdsa({
                message_hash = messageHash;
                derivation_path = derivationPath;
                key_id = keyId;
            });
            #ok(signature);
        } catch (e) {
            #err("Failed to sign message: " # Error.message(e));
        };
    };

    private func getDerivationPath(userId : ?Principal, derivedId : ?Text) : {
        derivationPath : [Blob];
        keyId : { curve : IC.EcdsaCurve; name : Text };
    } {
        let derivationPathBuffer = Buffer.Buffer<Blob>(2);
        switch (userId) {
            case (?userId) derivationPathBuffer.add(Principal.toBlob(userId));
            case (null) ();
        };
        switch (derivedId) {
            case (?derivedId) derivationPathBuffer.add(Text.encodeUtf8(derivedId));
            case (null) ();
        };
        let derivationPath = Buffer.toArray(derivationPathBuffer);
        let keyId = {
            curve = #secp256k1;
            // There are three options:
            // dfx_test_key: a default key ID that is used in deploying to a local version of IC (via IC SDK).
            // test_key_1: a master test key ID that is used in mainnet.
            // key_1: a master production key ID that is used in mainnet.
            name = "test_key_1"; // TODO
        };
        { derivationPath; keyId };
    };
};
