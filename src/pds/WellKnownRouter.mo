import RouteContext "mo:liminal@3/RouteContext";
import Route "mo:liminal@3/Route";
import DIDModule "./DID";
import KeyHandler "./Handlers/KeyHandler";
import DID "mo:did@3";
import DIDDocument "../atproto/DIDDocument";
import ServerInfo "./ServerInfo";
import AtUri "../atproto/AtUri";
import ServerInfoHandler "./Handlers/ServerInfoHandler";
import CertifiedAssets "mo:certified-assets@0";
import StableCertifiedAssets "mo:certified-assets@0/Stable";
import Text "mo:core@1/Text";

module {

  public class Router(
    serverInfoHandler : ServerInfoHandler.Handler,
    keyHandler : KeyHandler.Handler,
    certStore : CertifiedAssets.StableStore,
  ) = this {

    public func getDidDocument(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {
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

    public func getIcDomains(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
      // let serverInfo = serverInfoHandler.get();
      // let textValue = switch (serverInfo.serviceSubdomain) {
      //   case (?subdomain) subdomain # "." # serverInfo.hostname;
      //   case (null) serverInfo.hostname;
      // };
      // routeContext.buildResponse(#ok, #text(textValue));

      // TODO figure out a cleaner way to do this with certified assets
      let request : CertifiedAssets.HttpRequest = {
        url = routeContext.httpContext.request.url;
        method = routeContext.httpContext.request.method;
        headers = routeContext.httpContext.request.headers;
        body = routeContext.httpContext.request.body;
        certificate_version = routeContext.httpContext.certificateVersion;
      };
      let serverInfo = serverInfoHandler.get();
      let icDomains = getIcDomainsText(serverInfo);
      let icDomainsBlob = Text.encodeUtf8(icDomains);
      // status code, body, headers are the only things used for certification
      let response : CertifiedAssets.HttpResponse = {
        status_code = 200;
        headers = [("content-type", "text/html")];
        body = icDomainsBlob;
        streaming_strategy = null;
        upgrade = null;
      };

      switch (StableCertifiedAssets.get_certified_response(certStore, request, response, null)) {
        case (#ok(certifiedResponse)) routeContext.buildResponse(#ok, #custom({ body = certifiedResponse.body; headers = certifiedResponse.headers }));
        case (#err(e)) routeContext.buildResponse(#internalServerError, #error(#message("Failed to get certified response for url '" # routeContext.httpContext.request.url # "': " # e)));
      };
    };

    public func getAtprotoDid(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
      let serverInfo = serverInfoHandler.get();
      routeContext.buildResponse(#ok, #text(DID.Plc.toText(serverInfo.plcIdentifier)));
    };
  };

  public func getIcDomainsText(serverInfo : ServerInfo.ServerInfo) : Text {
    switch (serverInfo.serviceSubdomain) {
      case (?subdomain) subdomain # "." # serverInfo.hostname # "\n" # serverInfo.hostname; // include both with and without subdomain
      case (null) serverInfo.hostname;
    };
  };
};
