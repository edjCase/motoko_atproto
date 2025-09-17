import Text "mo:core@1/Text";
import PlcDID "mo:did@3/Plc";
import DID "mo:did@3";
import AtUri "./Types/AtUri";
import DIDDocument "Types/DIDDocument";
import Order "mo:core@1/Order";

module {

  public func comparePlcDID(did1 : DID.Plc.DID, did2 : DID.Plc.DID) : Order.Order {
    if (did1 == did2) return #equal;
    Text.compare(did1.identifier, did2.identifier);
  };

  // Generate the AT Protocol DID Document
  public func generateDIDDocument(
    did : DID.DID,
    alsoKnownAs : [Text],
    verificationPublicKey : DID.Key.DID,
  ) : DIDDocument.DIDDocument {
    let keyId = DID.toText(did) # "#atproto"; // TODO configurable keys
    {
      id = did;
      context = [
        "https://www.w3.org/ns/did/v1",
        "https://w3id.org/security/multikey/v1",
        "https://w3id.org/security/suites/secp256k1-2019/v1",
      ];
      alsoKnownAs = alsoKnownAs;
      verificationMethod = [{
        id = keyId;
        type_ = "Multikey";
        controller = did;
        publicKeyMultibase = ?verificationPublicKey;
      }];
      authentication = [keyId];
      assertionMethod = [keyId];
    };
  };

};
