import KeyHandler "./KeyHandler";
import DID "mo:did@3";
import JWT "mo:jwt@2";
import Result "mo:core@1/Result";
import Array "mo:core@1/Array";
import Debug "mo:core@1/Debug";
import Random "mo:core@1/Random";
import Json "mo:json@1";
import Time "mo:core@1/Time";
import SHA256 "mo:sha2/Sha256";

module {
  public type AccessTokenInfo = {
    token : Text;
    expiresAt : Int; // epoch seconds
  };
  public type RefreshTokenInfo = {
    token : Text;
    expiresAt : Int; // epoch seconds
  };

  public class Handler(keyHandler : KeyHandler.Handler) {

    public func validateAccessToken(
      verificationKey : JWT.SignatureVerificationKey,
      accessToken : Text,
    ) : async* Result.Result<DID.Plc.DID, Text> {
      // Parse and validate the JWT token
      let token = switch (JWT.parse(accessToken)) {
        case (#ok(token)) token;
        case (#err(e)) return #err("Invalid access token format: " # debug_show (e));
      };

      // Verify the token signature
      let validationOptions : JWT.ValidationOptions = {
        expiration = true; // Check token expiration
        notBefore = true; // Check token validity start time
        issuer = #skip; // Skip issuer validation
        audience = #skip; // Skip audience validation
        signature = #key(verificationKey); // Validate signature
      };

      switch (JWT.validate(token, validationOptions)) {
        case (#ok) ();
        case (#err(e)) return #err("Access token is invalid: " # e);
      };

      // Extract DID from token payload
      let ?("sub", #string(didText)) = Array.find<(Text, Json.Json)>(token.payload, func((key, _)) = key == "sub") else return #err("Missing 'sub' claim in token");

      let did = switch (DID.Plc.fromText(didText)) {
        case (#ok(did)) did;
        case (#err(e)) return #err("Invalid DID in token: " # e);
      };
      #ok(did);
    };

    public func generateAccessToken(
      actorId : DID.Plc.DID,
      serverId : DID.Web.DID,
      refreshTokenId : Text,
    ) : async* Result.Result<AccessTokenInfo, Text> {
      let now = Time.now();
      let issueTime = now / 1_000_000_000; // Convert to seconds from nanoseconds
      let accessExpiresAt = now + (60 * 60); // 1 hour in seconds

      // Generate access JWT (short-lived, 1 hour)
      let accessPayload : JWT.UnsignedToken = {
        header = [
          ("typ", #string("at+jwt")),
          ("alg", #string("ES256K")),
        ];
        payload = [
          ("scope", #string("com.atproto.refresh")),
          ("sub", #string(DID.Plc.toText(actorId))),
          ("aud", #string(DID.Web.toText(serverId))),
          ("jti", #string(refreshTokenId)),
          ("iat", #number(#int(issueTime))),
          ("exp", #number(#int(accessExpiresAt))),
        ];
      };
      let accessTokenMessage = JWT.toBlobUnsigned(accessPayload);
      let accessTokenMessageHash = SHA256.fromBlob(#sha256, accessTokenMessage);
      let accessTokenSignature = switch (await* keyHandler.sign(#verification, accessTokenMessageHash)) {
        case (#ok(sig)) sig;
        case (#err(err)) return #err("Failed to sign access token: " # err);
      };

      let accessJwt = JWT.toText({
        accessPayload with
        signature = {
          algorithm = "ES256K";
          value = accessTokenSignature;
          message = accessTokenMessage;
        };
      });

      #ok({
        token = accessJwt;
        expiresAt = accessExpiresAt;
      });
    };

    public func generateRefreshToken(
      actorId : DID.Plc.DID,
      serverId : DID.Web.DID,
    ) : async* Result.Result<RefreshTokenInfo, Text> {

      let now = Time.now();
      let issueTime = now / 1_000_000_000; // Convert to seconds from nanoseconds
      let refreshExpiresAt = now + (90 * 24 * 60 * 60); // 90 days in seconds
      // Generate refresh JWT (long-lived)
      let refreshPayload : JWT.UnsignedToken = {
        header = [
          ("typ", #string("refresh+jwt")),
          ("alg", #string("ES256K")),
        ];
        payload = [
          ("scope", #string("com.atproto.refresh")),
          ("sub", #string(DID.Plc.toText(actorId))),
          ("aud", #string(DID.Web.toText(serverId))),
          ("iat", #number(#int(issueTime))),
          ("exp", #number(#int(refreshExpiresAt))),
        ];
      };
      let refreshTokenMessage = JWT.toBlobUnsigned(refreshPayload);
      let refreshTokenMessageHash = SHA256.fromBlob(#sha256, refreshTokenMessage);
      let refreshTokenSignature = switch (
        await* keyHandler.sign(#rotation, refreshTokenMessageHash)
      ) {
        case (#ok(sig)) sig;
        case (#err(err)) return #err("Failed to sign refresh token: " # err);
      };

      let refreshJwt = JWT.toText({
        refreshPayload with
        signature = {
          algorithm = "ES256K";
          value = refreshTokenSignature;
          message = refreshTokenMessage;
        };
      });

      #ok({
        token = refreshJwt;
        expiresAt = refreshExpiresAt;
      });
    };
  };
};
