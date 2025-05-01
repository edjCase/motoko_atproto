import Text "mo:base/Text";
import Blob "mo:base/Blob";
import Result "mo:base/Result";

module {

    public type Request = {
        method : Method;
        nsid : Text;
    };

    public type Response = Result.Result<OkResponse, ErrResponse>;

    public type OkResponse = {
        contentType : Text;
        body : Blob;
    };

    public type ErrResponse = {
        error : Text;
        message : Text;
    };

    public type Method = {
        #get;
        #post : ?Blob;
    };

    public func process(request : Request) : Response {

        let json : Text = switch (request.nsid) {
            case ("_health") "{\"version\": \"0.0.1\"}";
            case ("com.atproto.server.describeServer") {
                let did = "did:web:edjcase.com";
                let availableUserDomains = "[\"edjcase.com\"]";
                let inviteCodeRequired = "true";
                let privacyPolicy = "";
                let termsOfService = "";
                let contactEmailAddress = "gekctek@edjcase.com";
                "{\"did\": \"" # did # "\", \"availableUserDomains\": " # availableUserDomains # ", \"inviteCodeRequired\": " # inviteCodeRequired # ", \"links\": { \"privacyPolicy\": \"" # privacyPolicy # "\", \"termsOfService\": \"" # termsOfService # "\" }, \"contact\": { \"email\": \"" # contactEmailAddress # "\" } }";
            };
            case (_) {
                // TODO
                let method = switch (request.method) {
                    case (#get) "GET";
                    case (#post(_)) "POST";
                };
                "{\"NSID\": \"" # request.nsid # "\", \"METHOD\": \"" # method # "\"}";
            };
        };

        #ok({
            contentType = "application/json";
            body = Text.encodeUtf8(json);
        });

    };
};
