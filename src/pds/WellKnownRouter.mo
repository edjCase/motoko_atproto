import Text "mo:base/Text";
import RouteContext "mo:liminal/RouteContext";
import Route "mo:liminal/Route";
import DID "./DID";
import KeyHandler "./Handlers/KeyHandler";
import KeyDID "mo:did/Key";
import ServerInfoHandler "./Handlers/ServerInfoHandler";
import Domain "mo:url-kit/Domain";

module {

    public class Router(
        serverInfoHandler : ServerInfoHandler.Handler,
        keyHandler : KeyHandler.Handler,
    ) = this {

        public func getDidDocument<system>(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {
            let publicKeyDID : KeyDID.DID = switch (await* keyHandler.getPublicKey(#verification)) {
                case (#ok(did)) did;
                case (#err(e)) return routeContext.buildResponse(#internalServerError, #error(#a()));
            };
            let didDoc = DID.generateDIDDocument(publicKeyDID, plcDid, webDid);
            let didDocJson = #object_([
                ("id", #text(didDoc.id)),
                ("context", #array(didDoc.context)),
                ("alsoKnownAs", #array(didDoc.alsoKnownAs)),
                ("verificationMethod", #array(didDoc.verificationMethod)),
                ("authentication", #array(didDoc.authentication)),
                ("assertionMethod", #array(didDoc.assertionMethod)),
            ]);
            routeContext.buildResponse(#ok, #json(didDocJson));
        };

        public func getIcDomains(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
            let ?serverInfo = serverInfoHandler.get() else return routeContext.buildResponse(#internalServerError, #text("Server not initialized"));
            routeContext.buildResponse(#ok, #text(Domain.toText(serverInfo.domain)));
        };
    };

};
