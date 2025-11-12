import RouteContext "mo:liminal@3/RouteContext";
import Route "mo:liminal@3/Route";
import Text "mo:core@1/Text";
import SubscribeRepos "../atproto/Lexicons/Com/Atproto/Sync/SubscribeRepos";
import RepositoryMessageHandler "./Handlers/RepositoryMessageHandler";
import Nat "mo:core@1/Nat";
import Iter "mo:core@1/Iter";
import Option "mo:core@1/Option";
import List "mo:core@1/List";
import DagCbor "mo:dag-cbor@2";
import Buffer "mo:buffer@0";
import BaseX "mo:base-x-encoder@2";
import Json "mo:json@1";
import Runtime "mo:core@1/Runtime";

module {

  public class Router(
    repositoryMessageHandler : RepositoryMessageHandler.Handler
  ) = this {

    public func getRepoMessages(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
      let sinceSeqParam = switch (routeContext.getQueryParam("sinceSeq")) {
        case (?sinceSeqText) {
          switch (Nat.fromText(sinceSeqText)) {
            case (?n) n;
            case (null) return routeContext.buildResponse(#badRequest, #error(#message("Invalid sinceSeq parameter")));
          };
        };
        case (null) 0; // Default to 0 if not provided
      };

      let messagesResult = repositoryMessageHandler.getMessages(sinceSeqParam);
      switch (messagesResult) {
        case (#ok(messages)) {
          let messagesJson : [Json.Json] = messages.vals()
          |> Iter.map(
            _,
            func(msg : RepositoryMessageHandler.Message) : Json.Json {
              let dagCborMessage = SubscribeRepos.toDagCbor(msg);
              let bytes = List.empty<Nat8>();
              let buffer = Buffer.fromList(bytes);
              switch (DagCbor.toBytesBuffer(buffer, dagCborMessage.header)) {
                case (#ok(_)) ();
                case (#err(e)) Runtime.trap("Failed to encode DAG-CBOR header: " # debug_show (e));
              };
              switch (DagCbor.toBytesBuffer(buffer, dagCborMessage.payload)) {
                case (#ok(_)) ();
                case (#err(e)) Runtime.trap("Failed to encode DAG-CBOR payload: " # debug_show (e));
              };
              #string(BaseX.toBase64(List.values(bytes), #standard({ includePadding = true })));
            },
          )
          |> Iter.toArray(_);
          let responseBody = #object_([
            ("messages", #array(messagesJson)),
          ]);
          routeContext.buildResponse(#ok, #json(responseBody));
        };
        case (#err(e)) {
          let (error, message) : (Text, Text) = switch (e) {
            case (#futureCursor) {
              ("FutureCursor", "The provided cursor is in the future.");
            };
            case (#consumerTooSlow({ message })) {
              ("ConsumerTooSlow", Option.get(message, ""));
            };
          };
          let errorJson = #object_([
            ("error", #string(error)),
            ("message", #string(message)),
          ]);
          routeContext.buildResponse(#badRequest, #json(errorJson));
        };
      };
    };
  };
};
