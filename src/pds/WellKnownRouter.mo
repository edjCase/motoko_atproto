import Text "mo:base/Text";
import Blob "mo:base/Blob";
import Result "mo:base/Result";
import Array "mo:new-base/Array";
import Nat64 "mo:new-base/Nat64";
import Bool "mo:new-base/Bool";
import Repository "./Types/Repository";
import RouteContext "mo:liminal/RouteContext";
import Liminal "mo:liminal";
import Route "mo:liminal/Route";
import Serde "mo:serde";
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
