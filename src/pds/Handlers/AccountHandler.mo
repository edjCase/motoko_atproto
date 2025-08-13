import PureMap "mo:core/pure/Map";
import Array "mo:base/Array";
import DID "mo:did";
import Result "mo:core/Result";
import CreateSession "../Types/Lexicons/Com/Atproto/Server/CreateSession";
import GetSession "../Types/Lexicons/Com/Atproto/Server/GetSession";
import CreateAccount "../Types/Lexicons/Com/Atproto/Server/CreateAccount";
import JWT "mo:jwt";
import PBKDF2 "mo:pbkdf2-sha512";
import DIDModule "../DID";
import Time "mo:core/Time";
import Random "mo:core/Random";
import SHA256 "mo:sha2/Sha256";
import TextX "mo:xtended-text/TextX";
import Blob "mo:base/Blob";
import DIDDocument "../Types/DIDDocument";
import IterX "mo:xtended-iter/IterX";
import BaseX "mo:base-x-encoder";
import KeyHandler "./KeyHandler";
import ServerInfoHandler "./ServerInfoHandler";
import Text "mo:core/Text";
import DIDDirectoryHandler "./DIDDirectoryHandler";
import Domain "mo:url-kit/Domain";
import Runtime "mo:core/Runtime";
import Json "mo:json";
import ECDSA "mo:ecdsa";
import Debug "mo:core/Debug";
import Iter "mo:core/Iter";

module {

  public type StableData = {
    accounts : PureMap.Map<DID.Plc.DID, AccountData>;
    sessions : PureMap.Map<Text, Session>;
  };

  public type Session = {
    did : DID.Plc.DID;
    createdAt : Time.Time;
    lastActiveAt : Time.Time;
    refreshTokenHash : Blob; // SHA256 hash of current refresh token
    refreshTokenId : Text; // For token rotation detection
    refreshExpiresAt : Time.Time;
    refreshCount : Nat; // Number of times this session has been refreshed
    lastRefreshAt : ?Time.Time; // Optional - null for new sessions
    revoked : ?RevokedInfo; // Optional - null unless revoked
  };

  public type RevokedInfo = {
    time : Time.Time;
    reason : Text; // Reason for revocation
  };

  public type AccountData = {
    handle : Text;
    email : ?Text;
    passwordHash : Blob;
    salt : Blob;
  };

  public type Account = AccountData and {
    id : DID.Plc.DID;
  };

  type CreateSessionResponse = {
    accessJwt : Text;
    refreshJwt : Text;
    handle : Text;
    did : DID.Plc.DID;
    didDoc : ?DIDDocument.DIDDocument;
  };

  public class Handler(
    stableData : StableData,
    keyHandler : KeyHandler.Handler,
    serverInfoHandler : ServerInfoHandler.Handler,
    didDirectoryHandler : DIDDirectoryHandler.Handler,
  ) {
    var sessions = stableData.sessions;
    var accounts = stableData.accounts;
    var handleMap = PureMap.entries(accounts)
    |> Iter.map<(DID.Plc.DID, AccountData), (Text, DID.Plc.DID)>(
      _,
      func((did, account) : (DID.Plc.DID, AccountData)) : (Text, DID.Plc.DID) {
        (account.handle, did);
      },
    )
    |> PureMap.fromIter(_, Text.compare); // TODO case sensitivity? TODO lazy load?

    public func get(id : DID.Plc.DID) : Result.Result<Account, Text> {
      let ?account = PureMap.get(accounts, DIDModule.comparePlcDID, id) else return #err("Account not found with id: " # DID.Plc.toText(id));
      #ok({
        account with
        id = id;
      });
    };

    public func getByHandle(handle : Text) : Result.Result<Account, Text> {
      let ?accountId = PureMap.get(handleMap, Text.compare, handle) else return #err("Account not found with handle: " # handle);
      get(accountId);
    };

    public func create(
      request : CreateAccount.Request
    ) : async* Result.Result<CreateAccount.Response, Text> {

      // Validate request
      if (TextX.isEmptyOrWhitespace(request.handle)) return #err("Handle cannot be empty");

      if (request.inviteCode != null) {
        // TODO
        return #err("Invite codes are not supported yet");
      };

      if (request.verificationCode != null) {
        // TODO
        return #err("Verification codes are not supported yet");
      };

      if (request.verificationPhone != null) {
        // TODO
        return #err("Phone verification is not supported yet");
      };

      if (request.recoveryKey != null) {
        // TODO
        return #err("Recovery keys are not supported yet");
      };

      if (request.plcOp != null) {
        // TODO
        return #err("PLC operations are not supported yet");
      };
      let password = switch (request.password) {
        case (?pwd) pwd;
        case (null) return #err("Passwordless account creation is not supported yet");
      };
      let did : DID.Plc.DID = switch (request.did) {
        case (?did) did;
        case (null) {
          let ?serverInfo = serverInfoHandler.get() else Runtime.trap("Server is not intiialized");
          let handle = request.handle # "." # Domain.toText(serverInfo.domain);
          let createRequest : DIDDirectoryHandler.CreatePlcRequest = {
            // TODO?
            alsoKnownAs = ["at://" # handle];
            // TODO?
            services = [{
              id = "atproto_pds";
              type_ = "AtprotoPersonalDataServer";
              endpoint = "https://" # Domain.toText(serverInfo.domain);
            }];
          };
          switch (await* didDirectoryHandler.create(createRequest)) {
            case (#ok(did)) did;
            case (#err(err)) return #err("Failed to create DID: " # err);
          };
        };
      };

      // Check if account already exists
      let null = PureMap.get<DID.Plc.DID, AccountData>(accounts, DIDModule.comparePlcDID, did) else return #err("Account already exists");

      let salt = await Random.blob();

      let passwordHash = PBKDF2.pbkdf2_sha512(
        #text(password),
        #blob(salt),
        4096,
        64,
      );

      // Create new account
      let newAccount : AccountData = {
        handle = request.handle;
        email = request.email;
        passwordHash = Blob.fromArray(passwordHash);
        salt = salt;
      };

      // Store the account in stable data
      let updatedAccounts = PureMap.add(accounts, DIDModule.comparePlcDID, did, newAccount);

      accounts := updatedAccounts; // TODO how to best handle async failure

      await* createSessionInternal(
        did,
        newAccount,
      );
    };

    public func createSession(
      request : CreateSession.Request
    ) : async* Result.Result<CreateSession.Response, Text> {
      if (not TextX.isNullOrEmptyOrWhitespace(request.authFactorToken)) {
        // TODO
        return #err("Authentication factor tokens are not supported yet");
      };

      // TODO no accounts can be taken down right now, so this is irrelevant right now
      // if (request.allowTakendown != null) {
      // };

      // Try parse the identifier as a DID, then email/handle
      let ?(did, account) = getAccountFromIdentifier(request.identifier) else return #err("Account not found for identifier: " # request.identifier);

      // Validate password
      let passwordHash = Blob.fromArray(
        PBKDF2.pbkdf2_sha512(
          #text(request.password),
          #blob(account.salt),
          4096,
          64,
        )
      );
      if (passwordHash != account.passwordHash) {
        return #err("Invalid password");
      };

      Result.chain<CreateSessionResponse, CreateSession.Response, Text>(
        await* createSessionInternal(did, account),
        func(res : CreateSessionResponse) : Result.Result<CreateSession.Response, Text> {
          #ok({
            res with
            email = account.email;
            emailConfirmed = null; // TODO: Implement email confirmation
            emailAuthFactor = null; // TODO: Implement email authentication factor
            active = null; // TODO: Implement active flag
            status = null; // TODO: Implement status description
          });
        },
      );
    };

    public func getSession(
      accessToken : Text
    ) : async* Result.Result<GetSession.Response, Text> {
      // Parse and validate the JWT token
      let token = switch (JWT.parse(accessToken)) {
        case (#ok(token)) token;
        case (#err(e)) return #err("Invalid access token format: " # debug_show (e));
      };

      let verificationPublicKey = switch (await* keyHandler.getPublicKey(#verification)) {
        case (#ok(pubKey)) pubKey;
        case (#err(err)) return #err("Failed to get verification public key: " # err);
      };

      let jwtKey = switch (verificationPublicKey.keyType) {
        case (#secp256k1) {
          switch (ECDSA.publicKeyFromBytes(verificationPublicKey.publicKey.vals(), #raw({ curve = ECDSA.secp256k1Curve() }))) {
            case (#ok(key)) #ecdsa(key);
            case (#err(e)) return #err("Failed to parse secp256k1 key bytes: " # e);
          };
        };
        case (#ed25519) Debug.todo();
        case (#p256) Debug.todo();
      };

      // Verify the token signature
      let validationOptions : JWT.ValidationOptions = {
        expiration = true; // Check token expiration
        notBefore = true; // Check token validity start time
        issuer = #skip; // Skip issuer validation
        audience = #skip; // Skip audience validation
        signature = #key(jwtKey); // Validate signature
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

      // Check if account exists
      let ?account = PureMap.get(accounts, DIDModule.comparePlcDID, did) else return #err("Account not found");

      // Check token expiration
      let expTime = switch (JWT.getPayloadValue(token, "exp")) {
        case (?#number(#int(expTime))) expTime;
        case (exp) return #err("Invalid 'exp' claim in token: " # debug_show (exp));
      };

      let currentTime = Time.now() / 1_000_000_000; // Convert to seconds

      if (currentTime >= expTime) {
        return #err("Access token has expired");
      };

      // Get server info for handle formatting
      let ?serverInfo = serverInfoHandler.get() else return #err("Server not initialized");

      let webDID = {
        host = #domain(serverInfo.domain);
        path = [];
        port = null;
      };
      let didDoc = DIDModule.generateDIDDocument(did, webDID, verificationPublicKey);

      #ok({
        handle = account.handle # "." # Domain.toText(serverInfo.domain);
        did = DID.Plc.toText(did);
        email = account.email;
        emailConfirmed = null; // TODO: Implement email confirmation
        emailAuthFactor = null; // TODO: Implement email authentication factor
        didDoc = ?didDoc;
        active = ?true; // TODO: Implement proper active status
        status = null; // TODO: Implement status based on account state
      });
    };

    public func toStableData() : StableData {
      {
        accounts = accounts;
        sessions = sessions;
      };
    };

    private func createSessionInternal(
      did : DID.Plc.DID,
      account : AccountData,
    ) : async* Result.Result<CreateSessionResponse, Text> {
      let ?serverInfo = serverInfoHandler.get() else return #err("Server not initialized");
      let webDID = {
        host = #domain(serverInfo.domain);
        path = [];
        port = null;
      };
      // Generate session identifiers
      let randomBytes = await Random.blob();
      let (bytesHalf1, bytesHalf2) = IterX.splitAt(randomBytes.vals(), randomBytes.size() / 2);

      let sessionId = "sess_" # BaseX.toBase64(bytesHalf1, #url({ includePadding = false }));
      let refreshTokenId = BaseX.toBase64(bytesHalf2, #url({ includePadding = false }));

      let now = Time.now();
      let issueTime = now / 1_000_000_000; // Convert to seconds from nanoseconds
      let accessExpiresAt = now + (60 * 60); // 1 hour in seconds
      let refreshExpiresAt = now + (90 * 24 * 60 * 60); // 90 days in seconds

      // Generate access JWT (short-lived, 1 hour)
      let accessPayload : JWT.UnsignedToken = {
        header = [
          ("typ", #string("at+jwt")),
          ("alg", #string("ES256K")),
        ];
        payload = [
          ("scope", #string("com.atproto.refresh")),
          ("sub", #string(DID.Plc.toText(did))),
          ("aud", #string(DID.Web.toText(webDID))),
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

      // Generate refresh JWT (long-lived)
      let refreshPayload : JWT.UnsignedToken = {
        header = [
          ("typ", #string("refresh+jwt")),
          ("alg", #string("ES256K")),
        ];
        payload = [
          ("scope", #string("com.atproto.refresh")),
          ("sub", #string(DID.Plc.toText(did))),
          ("aud", #string(DID.Web.toText(webDID))),
          ("jti", #string(refreshTokenId)),
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

      let refreshTokenHash = SHA256.fromBlob(#sha256, Text.encodeUtf8(refreshJwt));
      // Create new session
      let newSession : Session = {
        did = did;
        createdAt = now;
        lastActiveAt = now;
        refreshTokenHash = refreshTokenHash;
        refreshTokenId = refreshTokenId;
        refreshExpiresAt = refreshExpiresAt;
        refreshCount = 0;
        lastRefreshAt = null;
        revoked = null;
      };

      let verificationPublicKey = switch (await* keyHandler.getPublicKey(#verification)) {
        case (#ok(pubKey)) pubKey;
        case (#err(err)) return #err("Failed to get verification public key: " # err);
      };

      // Get DID document
      let didDoc = DIDModule.generateDIDDocument(did, webDID, verificationPublicKey);

      // Store the session in stable data (using sessionId as key, not token)
      sessions := PureMap.add(sessions, Text.compare, sessionId, newSession);

      // Return response
      #ok({
        accessJwt = accessJwt;
        refreshJwt = refreshJwt;
        handle = account.handle # "." # Domain.toText(serverInfo.domain);
        did = did;
        didDoc = ?didDoc;
      });
    };

    func getAccountFromIdentifier(identifier : Text) : ?(DID.Plc.DID, AccountData) {
      switch (DID.Plc.fromText(identifier)) {
        case (#ok(did)) {
          let ?account = PureMap.get(
            accounts,
            DIDModule.comparePlcDID,
            did,
          ) else return null;
          ?(did, account);
        };
        case (#err(_)) {
          label f for ((did, acc) in PureMap.entries(accounts)) {
            if (TextX.equalIgnoreCase(acc.handle, identifier)) {
              return ?(did, acc);
            };
            switch (acc.email) {
              case (null) ();
              case (?email) {
                if (TextX.equalIgnoreCase(email, identifier)) {
                  return ?(did, acc);
                };
              };
            };
            let ?serverInfo = serverInfoHandler.get() else Runtime.trap("Server not intialized");
            let domainText = "." # Domain.toText(serverInfo.domain);
            switch (Text.stripEnd(identifier, #text(domainText))) {
              case (null) ();
              case (?strippedId) {
                if (acc.handle == strippedId) {
                  return ?(did, acc);
                };
              };
            };
          };
          null;
        };
      };
    };
  };
};
