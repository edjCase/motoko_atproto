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
            case ("com.atproto.server.listRepos") {
                "{
    \"cursor\": \"1748318014419::did:plc:ia76kvnndjutgedggx2ibrem\",
    \"repos\": [
        {
            \"did\": \"did:plc:xnd7c75ouxsftdh2saf2oyu3\",
            \"head\": \"bafyreifckqehf2j2b32427vvdy7v2a2pzv2vy3rhkd4cpcqgxxgk3mozsi\",
            \"rev\": \"3lqwydh42bd2c\",
            \"active\": true
        },
        {
            \"did\": \"did:plc:ia76kvnndjutgedggx2ibrem\",
            \"head\": \"bafyreici6qqhtvn2cycg26oxa5qpdz6ij2a7hmabsodiviulya6iiyijsi\",
            \"rev\": \"3lqx56znrdd2c\",
            \"active\": true
        }
    ]
}";
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
