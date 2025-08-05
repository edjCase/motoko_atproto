import DID "mo:did";
import Json "mo:json";
import Result "mo:new-base/Result";
import DIDDocument "../../../../DIDDocument";

module {

  /// Request type for creating an authentication session
  public type Request = {
    /// Handle or other identifier supported by the server for the authenticating user
    identifier : Text;

    /// Password for the user
    password : Text;

    /// Optional authentication factor token
    authFactorToken : ?Text;

    /// When true, instead of throwing error for takendown accounts, a valid response with a narrow scoped token will be returned
    allowTakendown : ?Bool;
  };

  /// Response from a successful session creation
  public type Response = {
    /// Access JWT token
    accessJwt : Text;

    /// Refresh JWT token
    refreshJwt : Text;

    /// Handle of the authenticated user
    handle : Text;

    /// DID of the authenticated user
    did : DID.Plc.DID;

    /// Optional DID document
    didDoc : ?DIDDocument.DIDDocument;

    /// Optional email address
    email : ?Text;

    /// Optional email confirmation status
    emailConfirmed : ?Bool;

    /// Optional email authentication factor status
    emailAuthFactor : ?Bool;

    /// Optional active status
    active : ?Bool;

    /// Optional status description
    status : ?Text;
  };

  public func toJson(response : Response) : Json.Json {

    let didText = DID.Plc.toText(response.did);

    let didDocJson = switch (response.didDoc) {
      case (?didDoc) DIDDocument.toJson(didDoc);
      case (null) #null_;
    };

    let emailJson = switch (response.email) {
      case (?email) #string(email);
      case (null) #null_;
    };

    let emailConfirmedJson = switch (response.emailConfirmed) {
      case (?confirmed) #bool(confirmed);
      case (null) #null_;
    };

    let emailAuthFactorJson = switch (response.emailAuthFactor) {
      case (?authFactor) #bool(authFactor);
      case (null) #null_;
    };

    let activeJson = switch (response.active) {
      case (?active) #bool(active);
      case (null) #null_;
    };

    let statusJson = switch (response.status) {
      case (?status) #string(status);
      case (null) #null_;
    };

    #object_([
      ("accessJwt", #string(response.accessJwt)),
      ("refreshJwt", #string(response.refreshJwt)),
      ("handle", #string(response.handle)),
      ("did", #string(didText)),
      ("didDoc", didDocJson),
      ("email", emailJson),
      ("emailConfirmed", emailConfirmedJson),
      ("emailAuthFactor", emailAuthFactorJson),
      ("active", activeJson),
      ("status", statusJson),
    ]);
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {

    // Extract required fields

    let identifier = switch (Json.getAsText(json, "identifier")) {
      case (#ok(identifier)) identifier;
      case (#err(#pathNotFound)) return #err("Missing required field: identifier");
      case (#err(#typeMismatch)) return #err("Invalid identifier field, expected string");
    };

    let password = switch (Json.getAsText(json, "password")) {
      case (#ok(password)) password;
      case (#err(#pathNotFound)) return #err("Missing required field: password");
      case (#err(#typeMismatch)) return #err("Invalid password field, expected string");
    };

    // Extract optional fields

    let authFactorToken = switch (Json.getAsText(json, "authFactorToken")) {
      case (#ok(token)) ?token;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid authFactorToken field, expected string");
    };

    let allowTakendown = switch (Json.getAsBool(json, "allowTakendown")) {
      case (#ok(allow)) ?allow;
      case (#err(#pathNotFound)) null;
      case (#err(#typeMismatch)) return #err("Invalid allowTakendown field, expected boolean");
    };

    #ok({
      identifier = identifier;
      password = password;
      authFactorToken = authFactorToken;
      allowTakendown = allowTakendown;
    });
  };
};
