import DagCbor "mo:dag-cbor@2";
import Json "mo:json@1";
import Array "mo:core@1/Array";
import JsonDagCborMapper "../../../../JsonDagCborMapper";

module {

  /// Response type for com.atproto.identity.getRecommendedDidCredentials
  /// Describes the credentials that should be included in the DID doc of an account that is migrating to this service.
  public type Response = {
    /// Recommended rotation keys for PLC dids. Should be undefined (or ignored) for did:webs.
    rotationKeys : ?[Text];

    /// Also known as identifiers
    alsoKnownAs : [Text];

    /// Verification methods (type unknown in schema)
    verificationMethods : DagCbor.Value;

    /// Services (type unknown in schema)
    services : DagCbor.Value;
  };

  public func toJson(response : Response) : Json.Json {

    let verificationMethodsJson = JsonDagCborMapper.fromDagCbor(response.verificationMethods);
    let servicesJson = JsonDagCborMapper.fromDagCbor(response.services);
    let alsoKnownAsJson = #array(response.alsoKnownAs |> Array.map<Text, Json.Json>(_, func(aka : Text) : Json.Json = #string(aka)));

    let rotationKeysJson = switch (response.rotationKeys) {
      case (?keys) #array(keys |> Array.map<Text, Json.Json>(_, func(key : Text) : Json.Json = #string(key)));
      case (null) #null_;
    };

    #object_([
      ("rotationKeys", rotationKeysJson),
      ("alsoKnownAs", alsoKnownAsJson),
      ("verificationMethods", verificationMethodsJson),
      ("services", servicesJson),
    ]);
  };

};
