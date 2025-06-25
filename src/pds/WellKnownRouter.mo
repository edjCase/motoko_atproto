import Text "mo:base/Text";
import RouteContext "mo:liminal/RouteContext";
import Route "mo:liminal/Route";
import DID "../did";

module {

    public class Router() {

        public func getDidDocument<system>(_ : RouteContext.RouteContext) : async* Route.HttpResponse {
            let didDoc = switch (await* DID.generateDIDDocument("edjcase.com", null)) {
                // TODO
                case (#ok(doc)) doc;
                case (#err(err)) {
                    let json = "{\"error\": \"failed to generate DID document\", \"message\": \"" # err # "\"}";
                    return {
                        statusCode = 500;
                        headers = [("Content-Type", "application/json")];
                        body = ?Text.encodeUtf8(json);
                        streamingStrategy = null;
                    };
                };
            };
            {
                statusCode = 200;
                headers = [("Content-Type", "application/json")];
                body = ?Text.encodeUtf8(didDoc);
                streamingStrategy = null;
            };
        };

        public func getIcDomains(_ : RouteContext.RouteContext) : Route.HttpResponse {
            {
                statusCode = 200;
                headers = [("Content-Type", "text/plain")];
                body = ?Text.encodeUtf8("edjcase.com"); // TODO
                streamingStrategy = null;
            };
        };
    };

};
