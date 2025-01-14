import HttpTypes "mo:http-types";
import Text "mo:base/Text";
import Blob "mo:base/Blob";
import Iter "mo:base/Iter";
import Debug "mo:base/Debug";
import XrpcHandler "./XrpcHandler";
import HttpParser "mo:http-parser";

actor {
  public query func http_request(request : HttpTypes.Request) : async HttpTypes.Response {
    routeRequest(request, [handleXrpc]);
  };

  public func http_request_update(request : HttpTypes.UpdateRequest) : async HttpTypes.UpdateResponse {
    routeRequest(request, [handleXrpc]);
  };

  private func xrpcToHttpResponse(xrpcResponse : XrpcHandler.Response) : HttpTypes.Response {
    switch (xrpcResponse) {
      case (#ok(ok)) {
        {
          status_code = 200;
          headers = [
            ("Content-Type", ok.contentType),
          ];
          body = ok.body;
          streaming_strategy = null;
          upgrade = null;
        };
      };
      case (#err(err)) {

        let json = "{\"error\": \"" # err.error # "\", \"message\": \"" # err.message # "\"}";

        {
          status_code = 400; // TODO: map error to status code?
          headers = [("Content-Type", "application/json")];
          body = Text.encodeUtf8(json);
          streaming_strategy = null;
          upgrade = null;
        };
      };
    };
  };

  private func handleXrpc(request : HttpParser.ParsedHttpRequest) : ?HttpTypes.Response {
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
          headers = [];
          body = Text.encodeUtf8(json);
          streaming_strategy = null;
          upgrade = null;
        };
      };
    };
  };

  private func routeRequest(request : HttpTypes.UpdateRequest, routes : [(HttpParser.ParsedHttpRequest) -> ?HttpTypes.Response]) : HttpTypes.Response {
    Debug.print("http_request url: " # request.url);
    let parsedRequest = HttpParser.parse(request);
    label f for (route in routes.vals()) {
      let ?response = route(parsedRequest) else continue f;
      return response;
    };
    {
      status_code = 404;
      headers = [];
      body = Blob.fromArray([]);
      streaming_strategy = null;
      upgrade = null;
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
