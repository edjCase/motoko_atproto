import Json "mo:json";
import Result "mo:new-base/Result";

module {

    /// Request type for com.atproto.admin.updateAccountPassword
    /// Update the password for a user account as an administrator.
    public type Request = {
        /// DID of the account to update password for
        did : Text; // DID string

        /// New password for the account
        password : Text;
    };

    public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
        let did = switch (Json.getAsText(json, "did")) {
            case (#ok(did)) did;
            case (#err(#pathNotFound)) return #err("Missing required field: did");
            case (#err(#typeMismatch)) return #err("Invalid did field, expected string");
        };

        let password = switch (Json.getAsText(json, "password")) {
            case (#ok(password)) password;
            case (#err(#pathNotFound)) return #err("Missing required field: password");
            case (#err(#typeMismatch)) return #err("Invalid password field, expected string");
        };

        #ok({
            did = did;
            password = password;
        });
    };

};
