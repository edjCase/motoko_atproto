import Json "mo:json";
import Result "mo:new-base/Result";
import Defs "./Defs";

module {

    /// Request type for com.atproto.identity.resolveIdentity
    public type Request = {
        /// Handle or DID to resolve
        identifier : Text;
    };

    /// Response type for com.atproto.identity.resolveIdentity
    public type Response = Defs.IdentityInfo;

    /// Error types that can be returned by this endpoint
    public type Error = {
        #handleNotFound : { message : Text };
        #didNotFound : { message : Text };
        #didDeactivated : { message : Text };
    };

    public func toJson(response : Response) : Json.Json {
        Defs.identityInfoToJson(response);
    };

    public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
        let identifier = switch (Json.getAsText(json, "identifier")) {
            case (#ok(identifier)) identifier;
            case (#err(#pathNotFound)) return #err("Missing required field: identifier");
            case (#err(#typeMismatch)) return #err("Invalid identifier field, expected string");
        };

        #ok({
            identifier = identifier;
        });
    };
};
