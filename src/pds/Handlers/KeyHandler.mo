import Result "mo:core@1/Result";
import DID "mo:did@3";
import Blob "mo:core@1/Blob";
import Text "mo:core@1/Text";
import Error "mo:core@1/Error";
import { ic } "mo:ic@3";

module {
  public type StableData = {
    verificationDerivationPath : [Blob];
  };

  public type KeyKind = {
    #rotation;
    #verification;
  };

  public type HandlerInterface = {
    sign : (key : KeyKind, messageHash : Blob) -> async* Result.Result<Blob, Text>;
    getPublicKey : (key : KeyKind) -> async* Result.Result<DID.Key.DID, Text>;
  };

  public class Handler(stableData : StableData) : HandlerInterface = this {
    var verificationDerivationPath : [Blob] = stableData.verificationDerivationPath;
    var verificationPublicKeyCache : ?DID.Key.DID = null; // Cache the verification key to avoid repeated calls to ic.ecdsa_public_key
    var rotationPublicKeyCache : ?DID.Key.DID = null; // Cache the rotation key to avoid repeated calls to ic.ecdsa_public_key

    public func sign(key : KeyKind, messageHash : Blob) : async* Result.Result<Blob, Text> {
      let derivationPath = getDerivationPathForKey(key);
      try {
        let { signature } = await (with cycles = 26_153_846_153) ic.sign_with_ecdsa({
          derivation_path = derivationPath;
          key_id = {
            curve = #secp256k1;
            // There are three options:
            // dfx_test_key: a default key ID that is used in deploying to a local version of IC (via IC SDK).
            // test_key_1: a master test key ID that is used in mainnet.
            // key_1: a master production key ID that is used in mainnet.
            name = "test_key_1"; // TODO based on environment
          };
          message_hash = messageHash;
        });
        #ok(signature);
      } catch (e) {
        #err("Failed to sign message: " # Error.message(e));
      };
    };

    public func getPublicKey(key : KeyKind) : async* Result.Result<DID.Key.DID, Text> {
      // TODO validate that caching is ok
      let cachedKey = switch (key) {
        case (#rotation) rotationPublicKeyCache;
        case (#verification) verificationPublicKeyCache;
      };
      switch (cachedKey) {
        case (?key) return #ok(key);
        case (null) ();
      };
      let derivationPath = getDerivationPathForKey(key);
      try {
        let { public_key } = await ic.ecdsa_public_key({
          canister_id = null;
          derivation_path = derivationPath;
          key_id = {
            curve = #secp256k1;

            // There are three options:
            // dfx_test_key: a default key ID that is used in deploying to a local version of IC (via IC SDK).
            // test_key_1: a master test key ID that is used in mainnet.
            // key_1: a master production key ID that is used in mainnet.
            name = "test_key_1"; // TODO based on environment
          };
        });
        let didKey = {
          keyType = #secp256k1;
          publicKey = public_key;
        };
        switch (key) {
          case (#rotation) rotationPublicKeyCache := ?didKey;
          case (#verification) verificationPublicKeyCache := ?didKey;
        };
        #ok(didKey);
      } catch (e) {
        #err("Failed to get public key: " # Error.message(e));
      };
    };

    private func getDerivationPathForKey(key : KeyKind) : [Blob] {
      switch (key) {
        case (#rotation) [];
        case (#verification) verificationDerivationPath;
      };
    };

    public func toStableData() : StableData {
      return {
        verificationDerivationPath = verificationDerivationPath;
      };
    };
  };
};
