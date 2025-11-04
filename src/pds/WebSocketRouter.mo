import IcWebSocketCdk "mo:ic-websocket-cdk@0";
import IcWebSocketCdkState "mo:ic-websocket-cdk@0/State";
import IcWebSocketCdkTypes "mo:ic-websocket-cdk@0/Types";

module {

  public class Router() = this {

    public func onMessage(args : IcWebSocketCdk.OnMessageCallbackArgs) : async () {
      let app_msg : ?AppMessage = from_candid (args.message);
      let new_msg : AppMessage = switch (app_msg) {
        case (?msg) {
          { message = Text.concat(msg.message, " ping") };
        };
        case (null) {
          Debug.print("Could not deserialize message");
          return;
        };
      };

      Debug.print("Received message: " # debug_show (new_msg));

      await send_app_message(args.client_principal, new_msg);
    };

    /// A custom function to send the message to the client
    public func sendMessage(
      client_principal : IcWebSocketCdk.ClientPrincipal,
      msg : AppMessage,
    ) : async () {

      // here we call the send from the CDK!!
      switch (await IcWebSocketCdk.send(ws_state, client_principal, to_candid (msg))) {
        case (#Err(err)) {
          Debug.print("Could not send message:" # debug_show (#Err(err)));
        };
        case (_) {};
      };
    };

    public func onOpen(args : IcWebSocketCdk.OnOpenCallbackArgs) : async () {
      Debug.print("New connection opened for client: " # debug_show (args.client_principal));
    };
    public func onClose(args : IcWebSocketCdk.OnCloseCallbackArgs) : async () {
      Debug.print("Connection closed for client: " # debug_show (args.client_principal));
    };
  };
};
