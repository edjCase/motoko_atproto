import DID "mo:did@2";
import DIDDocument "../../../../DIDDocument";
import Json "mo:json@1";
import Array "mo:core@1/Array";

module {

  /// Request type for describing a repository
  public type Request = {
    /// The handle or DID of the repo
    repo : DID.Plc.DID;
  };

  /// Response from a successful describe repo operation
  public type Response = {
    /// The handle for this account
    handle : Text;

    /// The DID for this account
    did : DID.Plc.DID;

    /// The complete DID document for this account
    didDoc : DIDDocument.DIDDocument;

    /// List of all the collections (NSIDs) for which this repo contains at least one record
    collections : [Text];

    /// Indicates if handle is currently valid (resolves bi-directionally)
    handleIsCorrect : Bool;
  };

  public func toJson(response : Response) : Json.Json {

    let didText = DID.Plc.toText(response.did);
    let didDocJson = DIDDocument.toJson(response.didDoc);
    let collectionsJson = response.collections |> Array.map<Text, Json.Json>(
      _,
      func(collection : Text) : Json.Json = #string(collection),
    );

    #object_([
      ("handle", #string(response.handle)),
      ("did", #string(didText)),
      ("didDoc", didDocJson),
      ("collections", #array(collectionsJson)),
      ("handleIsCorrect", #bool(response.handleIsCorrect)),
    ]);
  };
};
