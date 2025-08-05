import DID "mo:did";
import Json "mo:json";
import Array "mo:new-base/Array";
import Text "mo:base/Text";

module {

  public type DIDDocument = {
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
    publicKeyMultibase : ?DID.Key.DID;
  };

  public func toJson(didDoc : DIDDocument) : Json.Json {

    let verificationMethodsJson = didDoc.verificationMethod
    |> Array.map<VerificationMethod, Json.Json>(
      _,
      func(vm : VerificationMethod) : Json.Json = #object_([
        ("id", #string(vm.id)),
        ("type", #string(vm.type_)),
        ("controller", #string(DID.toText(vm.controller))),
        (
          "publicKeyMultibase",
          switch (vm.publicKeyMultibase) {
            case (null) #null_;
            case (?publicKey) #string(DID.Key.toText(publicKey, #base58btc));
          },
        ),
      ]),
    );

    let textArrayToJson = func(texts : [Text]) : Json.Json {
      #array(texts |> Array.map<Text, Json.Json>(_, func(text : Text) : Json.Json = #string(text)));
    };

    #object_([
      ("id", #string(DID.toText(didDoc.id))),
      ("context", textArrayToJson(didDoc.context)),
      ("alsoKnownAs", textArrayToJson(didDoc.alsoKnownAs)),
      ("verificationMethod", #array(verificationMethodsJson)),
      ("authentication", textArrayToJson(didDoc.authentication)),
      ("assertionMethod", textArrayToJson(didDoc.assertionMethod)),
    ]);
  };
};
