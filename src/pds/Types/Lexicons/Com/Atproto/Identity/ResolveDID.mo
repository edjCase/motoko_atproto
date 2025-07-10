import DID "mo:did";
import DagCbor "mo:dag-cbor";
import Json "mo:json";
import Result "mo:new-base/Result";
import JsonDagCborMapper "../../../../../JsonDagCborMapper";

module {

    /// Request type for com.atproto.identity.resolveDid
    public type Request = {
        /// DID to resolve
        did : DID.Plc.DID;
    };

    /// Response type for com.atproto.identity.resolveDid
    public type Response = {
        /// The complete DID document for the identity
        didDoc : DagCbor.Value;
    };

    /// Error types that can be returned by this endpoint
    public type Error = {
        #didNotFound : { message : Text };
        #didDeactivated : { message : Text };
    };

    public func toJson(response : Response) : Json.Json {
        let didDocJson = JsonDagCborMapper.fromDagCbor(response.didDoc);

        #object_([
            ("didDoc", didDocJson),
        ]);
    };

    public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
        let didText = switch (Json.getAsText(json, "did")) {
            case (#ok(did)) did;
            case (#err(#pathNotFound)) return #err("Missing required field: did");
            case (#err(#typeMismatch)) return #err("Invalid did field, expected string");
        };

        let did = switch (DID.Plc.fromText(didText)) {
            case (#ok(did)) did;
            case (#err(e)) return #err("Invalid DID: " # e);
        };

        #ok({
            did = did;
        });
    };
};
