import App "mo:liminal@1/App";
import HttpContext "mo:liminal@1/HttpContext";
import KeyHandler "../Handlers/KeyHandler";
import JWTMiddleware "mo:liminal@1/Middleware/JWT";
import Debug "mo:core@1/Debug";
import ECDSA "mo:ecdsa@7";
import DID "mo:did@3";

module {
  public func new(keyHandler : KeyHandler.Handler) : App.Middleware {
    {
      name = "AuthMiddleware";
      handleQuery = func(context : HttpContext.HttpContext, next : App.Next) : App.QueryResult {
        // TODO allow query? issue is with getting public key
        // maybe just see if the jwt is there, try get key from cache, then upgrade if not cached and has jwt
        next(); // Just pass through
      };
      handleUpdate = func(context : HttpContext.HttpContext, next : App.NextAsync) : async* App.HttpResponse {

        let publicKey = switch (await* keyHandler.getPublicKey(#verification)) {
          case (#ok(pubKey)) pubKey;
          case (#err(err)) {
            let message = "Failed to get verification public key: " # err;
            context.log(#error, message);
            return context.buildResponse(#internalServerError, #text(message));
          };
        };
        let jwtKey = switch (publicKey.keyType) {
          case (#secp256k1) {
            switch (ECDSA.publicKeyFromBytes(publicKey.publicKey.vals(), #raw({ curve = ECDSA.secp256k1Curve() }))) {
              case (#ok(key)) #ecdsa(key);
              case (#err(e)) {
                let message = "Failed to parse secp256k1 key bytes: " # e;
                context.log(#error, message);
                return context.buildResponse(#internalServerError, #text(message));
              };
            };
          };
          case (#ed25519) Debug.todo(); // TODO?
          case (#p256) Debug.todo(); // TODO?
        };

        let options = {
          expiration = true; // Check token expiration
          notBefore = true; // Check token validity start time
          issuer = #skip; // TODO
          audience = #skip; //TODO
          signature = #key(jwtKey); // Validate signature
        };
        let locations = JWTMiddleware.defaultLocations;

        // Will allow getting from HttpContext.getIdentity();
        JWTMiddleware.tryParseAndSetJWT(context, options, locations);

        await* next();
      };
    };
  };
};
