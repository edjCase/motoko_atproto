import Json "mo:json";
import Result "mo:new-base/Result";

module {

    /// Request type for com.atproto.admin.updateAccountEmail
    /// Administrative action to update an account's email.
    public type Request = {
        /// The handle or DID of the repo
        account : Text; // AT-identifier string

        /// New email address for the account
        email : Text;
    };

    public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
        let account = switch (Json.getAsText(json, "account")) {
            case (#ok(account)) account;
            case (#err(#pathNotFound)) return #err("Missing required field: account");
            case (#err(#typeMismatch)) return #err("Invalid account field, expected string");
        };

        let email = switch (Json.getAsText(json, "email")) {
            case (#ok(email)) email;
            case (#err(#pathNotFound)) return #err("Missing required field: email");
            case (#err(#typeMismatch)) return #err("Invalid email field, expected string");
        };

        #ok({
            account = account;
            email = email;
        });
    };

};
