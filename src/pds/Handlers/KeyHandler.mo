import Result "mo:core/Result";
import DID "mo:did";
import Blob "mo:core/Blob";
import Text "mo:core/Text";
import Error "mo:core/Error";
import { ic } "mo:ic";

module {
  public type StableData = {
    verificationDerivationPath : [Blob];
  };

  public type KeyKind = {
    #rotation;
    #verification;
  };

  public class Handler(stableData : StableData) = this {
    var verificationDerivationPath : [Blob] = stableData.verificationDerivationPath;

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
        #ok({
          keyType = #secp256k1;
          publicKey = public_key;
        });
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
