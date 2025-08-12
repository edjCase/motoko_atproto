import DID "mo:did";
import DagCbor "mo:dag-cbor";
import Json "mo:json";
import JsonDagCborMapper "../../../../../JsonDagCborMapper";

module {

  /// Identity information for an account
  public type IdentityInfo = {
    /// The DID of the account
    did : DID.Plc.DID;

    /// The validated handle of the account; or 'handle.invalid' if the handle did not bi-directionally match the DID document
    handle : Text;

    /// The complete DID document for the identity (type unknown in schema)
    didDoc : DagCbor.Value;
  };

  public func identityInfoToJson(info : IdentityInfo) : Json.Json {
    let didText = DID.Plc.toText(info.did);
    let didDocJson = JsonDagCborMapper.fromDagCbor(info.didDoc);

    #object_([
      ("did", #string(didText)),
      ("handle", #string(info.handle)),
      ("didDoc", didDocJson),
    ]);
  };
};
