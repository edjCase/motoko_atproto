import Json "mo:json";

module {
    // com.atproto.server.requestEmailUpdate
    // Request a token in order to update email.

    public type Response = {
        tokenRequired : Bool;
    };

    public func toJson(response : Response) : Json.Json {
        #object_([("tokenRequired", #bool(response.tokenRequired))]);
    };

};
