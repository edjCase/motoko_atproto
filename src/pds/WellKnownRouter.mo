import RouteContext "mo:liminal@1/RouteContext";
import Route "mo:liminal@1/Route";
import DIDModule "./DID";
import KeyHandler "./Handlers/KeyHandler";
import Domain "mo:url-kit@3/Domain";
import DID "mo:did@3";
import DIDDocument "../atproto/DIDDocument";
import ServerInfo "./ServerInfo";
import AtUri "../atproto/AtUri";
import ServerInfoHandler "./Handlers/ServerInfoHandler";

module {

  public class Router(
    serverInfoHandler : ServerInfoHandler.Handler,
    keyHandler : KeyHandler.Handler,
  ) = this {

    public func getDidDocument<system>(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {
      let serverInfo = serverInfoHandler.get();
      let publicKey : DID.Key.DID = switch (await* keyHandler.getPublicKey(#verification)) {
        case (#ok(did)) did;
        case (#err(e)) return routeContext.buildResponse(#internalServerError, #error(#message("Failed to get verification public key: " # e)));
      };
      let webDid = ServerInfo.buildWebDID(serverInfo);
      let alsoKnownAs = [AtUri.toText({ authority = #plc(serverInfo.plcIdentifier); collection = null })];
      let didDoc = DIDModule.generateDIDDocument(#web(webDid), alsoKnownAs, publicKey);
      let didDocJson = DIDDocument.toJson(didDoc);
      routeContext.buildResponse(#ok, #json(didDocJson));
    };

    public func getIcDomains<system>(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
      let serverInfo = serverInfoHandler.get();
      routeContext.buildResponse(#ok, #text(serverInfo.hostname));
    };

    public func getAtprotoDid<system>(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
      let serverInfo = serverInfoHandler.get();
      routeContext.buildResponse(#ok, #text(DID.Plc.toText(serverInfo.plcIdentifier)));
    };
  };
};
