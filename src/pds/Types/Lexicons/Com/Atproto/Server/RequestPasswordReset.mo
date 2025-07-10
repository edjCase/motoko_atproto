import Json "mo:json";

module {
    // com.atproto.server.requestPasswordReset
    // Initiate a user account password reset via email.

    public type Request = {
        email : Text;
    };

    public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
        let email = switch (Json.getAsText(json, "email")) {
            case (#ok(e)) e;
            case (#err(#pathNotFound)) return #err("Missing required field: email");
            case (#err(#typeMismatch)) return #err("Invalid email field, expected string");
        };
        #ok({
            email = email;
        });
    };

};
