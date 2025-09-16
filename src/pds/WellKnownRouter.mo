import RouteContext "mo:liminal@1/RouteContext";
import Route "mo:liminal@1/Route";
import DIDModule "./DID";
import KeyHandler "./Handlers/KeyHandler";
import ServerInfoHandler "./Handlers/ServerInfoHandler";
import Domain "mo:url-kit@3/Domain";
import DID "mo:did@3";
import JsonDagCborMapper "./JsonDagCborMapper";
import DIDDocument "./Types/DIDDocument";

module {

  public class Router(
    serverInfoHandler : ServerInfoHandler.Handler,
    keyHandler : KeyHandler.Handler,
  ) = this {

    public func getDidDocument<system>(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {
      let ?serverInfo = serverInfoHandler.get() else return routeContext.buildResponse(#internalServerError, #text("Server not initialized"));
      let publicKey : DID.Key.DID = switch (await* keyHandler.getPublicKey(#verification)) {
        case (#ok(did)) did;
        case (#err(e)) return routeContext.buildResponse(#internalServerError, #error(#message("Failed to get verification public key: " # e)));
      };
      let webDid : DID.Web.DID = {
        hostname = serverInfo.hostname;
        path = [];
        port = null;
      };
      let didDoc = DIDModule.generateDIDDocument(serverInfo.plcDid, webDid, publicKey);
      let didDocJson = DIDDocument.toJson(didDoc);
      routeContext.buildResponse(#ok, #json(didDocJson));
    };

    public func getIcDomains<system>(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
      let ?serverInfo = serverInfoHandler.get() else return routeContext.buildResponse(#internalServerError, #text("Server not initialized"));
      routeContext.buildResponse(#ok, #text(serverInfo.hostname));
    };
  };

};
