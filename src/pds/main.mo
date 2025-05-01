import HttpTypes "mo:http-types";
import Text "mo:base/Text";
import Iter "mo:base/Iter";
import HashMap "mo:base/HashMap";
import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Int "mo:base/Int";
import Time "mo:base/Time";
import XrpcHandler "./XrpcHandler";
import HttpParser "mo:http-parser";
import CertifiedCache "mo:certified-cache";
import DID "../did";

actor {

  let urls = HashMap.HashMap<Text, ()>(10, Text.equal, Text.hash);

  type CachedResponse = {
    body : Blob;
    headers : [HttpTypes.Header];
  };
  stable var certifiedCacheEntries : [(Text, (CachedResponse, Nat))] = [];
  let two_days_in_nanos = 2 * 24 * 60 * 60 * 1000 * 1000 * 1000; // 2 days in nanoseconds
  var certifiedCache = CertifiedCache.fromEntries<Text, CachedResponse>(
    certifiedCacheEntries,
    Text.equal,
    Text.hash,
    Text.encodeUtf8,
    func(b : CachedResponse) : Blob { b.body },
    two_days_in_nanos + Int.abs(Time.now()),
  );

  public query func getUrls() : async [Text] {
    urls.keys() |> Iter.toArray(_);
  };

  public query func http_request(request : HttpTypes.Request) : async HttpTypes.Response {
    let cachedResponseOrNull = certifiedCache.get(request.url);
    switch (cachedResponseOrNull) {
      case (?response) {
        {
          status_code : Nat16 = 200;
          headers = Array.append(response.headers, [certifiedCache.certificationHeader(request.url)]);
          body = response.body;
          streaming_strategy = null;
          upgrade = null;
        };
      };
      case (null) {
        // Upgrade request to get certified response
        {
          status_code = 200;
          headers = [];
          body = Blob.fromArray([]);
          streaming_strategy = null;
          upgrade = ?true;
        };
      };
    };
  };

  public func http_request_update(request : HttpTypes.UpdateRequest) : async HttpTypes.UpdateResponse {
    let parsedRequest = HttpParser.parse(request);
    urls.put(parsedRequest.url.path.original, ());
    let routes : [(HttpParser.ParsedHttpRequest) -> async* ?HttpTypes.Response] = [
      handleXrpc,
      handleStatic,
    ];
    label f for (route in routes.vals()) {
      let ?response = await* route(parsedRequest) else continue f;
      certifiedCache.put(
        parsedRequest.url.path.original,
        {
          body = response.body;
          headers = response.headers;
        },
        null,
      );
      return response;
    };
    {
      status_code = 200;
      headers = [("Content-Type", "text/plain")];
      body = Text.encodeUtf8("This is the PDS server");
      streaming_strategy = null;
      upgrade = null;
    };
  };

  let xrpcResponseHeaders = [("Access-Control-Allow-Origin", "*"), ("Access-Control-Allow-Methods", "GET, POST"), ("Access-Control-Allow-Headers", "atproto-accept-labelers")];

  private func xrpcToHttpResponse(xrpcResponse : XrpcHandler.Response) : HttpTypes.Response {
    switch (xrpcResponse) {
      case (#ok(ok)) {
        {
          status_code = 200;
          headers = Array.append(
            xrpcResponseHeaders,
            [
              ("Content-Type", ok.contentType),
            ],
          );
          body = ok.body;
          streaming_strategy = null;
          upgrade = null;
        };
      };
      case (#err(err)) {

        let json = "{\"error\": \"" # err.error # "\", \"message\": \"" # err.message # "\"}";

        {
          status_code = 400; // TODO: map error to status code?
          headers = Array.append(xrpcResponseHeaders, [("Content-Type", "application/json")]);
          body = Text.encodeUtf8(json);
          streaming_strategy = null;
          upgrade = null;
        };
      };
    };
  };

  private func handleXrpc(request : HttpParser.ParsedHttpRequest) : async* ?HttpTypes.Response {
    switch (tryParseXrpcRequest(request)) {
      case (#notXrpc) null;
      case (#xrpc(xrpcRequest)) {
        let xrpcResponse = XrpcHandler.process(xrpcRequest);
        ?xrpcToHttpResponse(xrpcResponse);
      };
      case (#invalidXrpc(msg)) {
        let json = "{\"error\": \"invalid\", \"message\": \"" # msg # "\"}";
        ?{
          status_code = 400;
          headers = Array.append(xrpcResponseHeaders, [("Content-Type", "application/json")]);
          body = Text.encodeUtf8(json);
          streaming_strategy = null;
          upgrade = null;
        };
      };
    };
  };

  private func handleStatic(request : HttpParser.ParsedHttpRequest) : async* ?HttpTypes.Response {
    switch (request.url.path.original) {
      case ("/.well-known/did.json") {
        let didDoc = switch (await* DID.generateDIDDocument("edjcase.com", null)) {
          // TODO
          case (#ok(doc)) doc;
          case (#err(err)) {
            let json = "{\"error\": \"failed to generate DID document\", \"message\": \"" # err # "\"}";
            return ?{
              status_code = 500;
              headers = [("Content-Type", "application/json")];
              body = Text.encodeUtf8(json);
              streaming_strategy = null;
              upgrade = null;
            };
          };
        };
        ?{
          status_code = 200;
          headers = [("Content-Type", "application/json")];
          body = Text.encodeUtf8(didDoc);
          streaming_strategy = null;
          upgrade = null;
        };
      };
      case ("/.well-known/ic-domains") {
        ?{
          status_code = 200;
          headers = [("Content-Type", "text/plain")];
          body = Text.encodeUtf8("edjcase.com"); // TODO
          streaming_strategy = null;
          upgrade = null;
        };
      };
      case (_) null;
    };
  };

  type TryParseXrpcResult = {
    #notXrpc;
    #xrpc : XrpcHandler.Request;
    #invalidXrpc : Text;
  };

  private func tryParseXrpcRequest(request : HttpParser.ParsedHttpRequest) : TryParseXrpcResult {
    if (request.url.path.array.size() < 1) return #notXrpc;
    if (request.url.path.array[0] != "xrpc") return #notXrpc;
    if (request.url.path.array.size() < 2) return #invalidXrpc("XRPC request must have a namespace id: /xrpc/{nsid}");
    let nsid = request.url.path.array[1];
    let method : XrpcHandler.Method = switch (request.method) {
      case ("GET") #get;
      case ("POST") switch (request.body) {
        case (?body) #post(?body.original);
        case (null) #post(null);
      };
      case (_) {
        return #invalidXrpc("METHOD NOT SUPPORTED for XRPC: " # request.method);
      };
    };
    let params : [(Text, Text)] = request.url.queryObj.trieMap.entries() |> Iter.toArray(_);
    return #xrpc({
      method = method;
      nsid = nsid;
      params = params;
    });
  };

};
