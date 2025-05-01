import Text "mo:base/Text";
import Iter "mo:base/Iter";
import HashMap "mo:base/HashMap";
import Array "mo:base/Array";
import XrpcHandler "./XrpcHandler";
import RouterMiddleware "mo:liminal/Middleware/Router";
import CompressionMiddleware "mo:liminal/Middleware/Compression";
import CORSMiddleware "mo:liminal/Middleware/CORS";
import JWTMiddleware "mo:liminal/Middleware/JWT";
import Liminal "mo:liminal";
import App "mo:liminal/App";
import Router "mo:liminal/Router";
import Route "mo:liminal/Route";
import Debug "mo:new-base/Debug";
import DID "../did";

actor {

  let urls = HashMap.HashMap<Text, ()>(10, Text.equal, Text.hash);

  public query func getUrls() : async [Text] {
    urls.keys() |> Iter.toArray(_);
  };

  private func loggingMiddleware() : App.Middleware {
    {
      handleQuery = func(context : Liminal.HttpContext, next : App.Next) : App.QueryResult {
        next();
      };
      handleUpdate = func(context : Liminal.HttpContext, next : App.NextAsync) : async* App.HttpResponse {
        Debug.print("Update request: " # context.request.url);
        urls.put(context.request.url, ());
        await* next();
      };
    };
  };

  let xrpcResponseHeaders = [
    ("Access-Control-Allow-Origin", "*"),
    ("Access-Control-Allow-Methods", "GET, POST"),
    ("Access-Control-Allow-Headers", "atproto-accept-labelers"),
  ];

  private func xrpcToHttpResponse(xrpcResponse : XrpcHandler.Response) : App.HttpResponse {
    switch (xrpcResponse) {
      case (#ok(ok)) {
        {
          statusCode = 200;
          headers = Array.append(
            xrpcResponseHeaders,
            [
              ("Content-Type", ok.contentType),
            ],
          );
          body = ?ok.body;
          streamingStrategy = null;
        };
      };
      case (#err(err)) {

        let json = "{\"error\": \"" # err.error # "\", \"message\": \"" # err.message # "\"}";

        {
          statusCode = 400; // TODO: map error to status code?
          headers = Array.append(xrpcResponseHeaders, [("Content-Type", "application/json")]);
          body = ?Text.encodeUtf8(json);
          streamingStrategy = null;
        };
      };
    };
  };

  let routerConfig : RouterMiddleware.Config = {
    prefix = null;
    identityRequirement = null;
    routes = [
      Router.getQuery(
        "/xrpc/{nsid}",
        func(routeContext : Route.RouteContext) : App.HttpResponse {
          let nsid = routeContext.getRouteParam("nsid");
          let response = XrpcHandler.process({
            method = #get;
            nsid = nsid;
          });
          xrpcToHttpResponse(response);
        },
      ),
      Router.postUpdate(
        "/xrpc/{nsid}",
        func<system>(routeContext : Route.RouteContext) : App.HttpResponse {
          let nsid = routeContext.getRouteParam("nsid");
          let response = XrpcHandler.process({
            method = #post(?routeContext.httpContext.request.body);
            nsid = nsid;
          });
          xrpcToHttpResponse(response);
        },
      ),
      Router.getAsyncUpdate(
        "/.well-known/did.json",
        func<system>(routeContext : Route.RouteContext) : async* App.HttpResponse {
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
        },
      ),
      Router.getQuery(
        "/.well-known/ic-domains",
        func(routeContext : Route.RouteContext) : App.HttpResponse {
          {
            statusCode = 200;
            headers = [("Content-Type", "text/plain")];
            body = ?Text.encodeUtf8("edjcase.com"); // TODO
            streamingStrategy = null;
          };
        },
      ),
    ];
  };

  // Http App
  let app = Liminal.App({
    middleware = [
      loggingMiddleware(),
      CompressionMiddleware.default(),
      CORSMiddleware.default(),
      JWTMiddleware.new({
        locations = JWTMiddleware.defaultLocations;
        validation = {
          audience = #skip;
          issuer = #skip;
          signature = #skip;
          notBefore = false;
          expiration = false;
        };
      }),
      // RequireAuthMiddleware.new(#authenticated),
      RouterMiddleware.new(routerConfig),
    ];
    errorSerializer = Liminal.defaultJsonErrorSerializer;
    candidRepresentationNegotiator = Liminal.defaultCandidRepresentationNegotiator;
  });

  // Http server methods

  public query func http_request(request : Liminal.RawQueryHttpRequest) : async Liminal.RawQueryHttpResponse {
    app.http_request(request);
  };

  public func http_request_update(request : Liminal.RawUpdateHttpRequest) : async Liminal.RawUpdateHttpResponse {
    await* app.http_request_update(request);
  };

};
