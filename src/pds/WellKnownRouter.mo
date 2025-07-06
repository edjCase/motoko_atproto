import Text "mo:base/Text";
import RouteContext "mo:liminal/RouteContext";
import Route "mo:liminal/Route";
import DIDModule "./DID";
import KeyHandler "./Handlers/KeyHandler";
import ServerInfoHandler "./Handlers/ServerInfoHandler";
import Domain "mo:url-kit/Domain";
import Json "mo:json";
import Array "mo:new-base/Array";
import DID "mo:did";
import JsonSerializer "./JsonSerializer";

module {

    public class Router(
        serverInfoHandler : ServerInfoHandler.Handler,
        keyHandler : KeyHandler.Handler,
    ) = this {

        public func getDidDocument<system>(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {
            let ?info = serverInfoHandler.get() else return routeContext.buildResponse(#internalServerError, #text("Server not initialized"));
            let publicKey : DID.Key.DID = switch (await* keyHandler.getPublicKey(#verification)) {
                case (#ok(did)) did;
                case (#err(e)) return routeContext.buildResponse(#internalServerError, #error(#message("Failed to get verification public key: " # e)));
            };
            let webDid : DID.Web.DID = {
                host = #domain(info.domain);
                path = [];
                port = null;
            };
            let didDoc = DIDModule.generateDIDDocument(info.plcDid, webDid, publicKey);
            let didDocJson = JsonSerializer.fromDidDocument(didDoc);
            routeContext.buildResponse(#ok, #json(didDocJson));
        };

        public func getIcDomains<system>(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
            let ?serverInfo = serverInfoHandler.get() else return routeContext.buildResponse(#internalServerError, #text("Server not initialized"));
            routeContext.buildResponse(#ok, #text(Domain.toText(serverInfo.domain)));
        };
    };

};
