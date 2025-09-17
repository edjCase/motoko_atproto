import PureMap "mo:core@1/pure/Map";
import Array "mo:core@1/Array";
import DID "mo:did@3";
import Result "mo:core@1/Result";
import CreateSession "../Types/Lexicons/Com/Atproto/Server/CreateSession";
import GetSession "../Types/Lexicons/Com/Atproto/Server/GetSession";
import CreateAccount "../Types/Lexicons/Com/Atproto/Server/CreateAccount";
import PBKDF2 "mo:pbkdf2-sha512@1";
import DIDModule "../DID";
import Time "mo:core@1/Time";
import Random "mo:core@1/Random";
import SHA256 "mo:sha2/Sha256";
import TextX "mo:xtended-text@2/TextX";
import Blob "mo:core@1/Blob";
import DIDDocument "../Types/DIDDocument";
import IterX "mo:xtended-iter@1/IterX";
import BaseX "mo:base-x-encoder@2";
import KeyHandler "./KeyHandler";
import ServerInfoHandler "./ServerInfoHandler";
import Text "mo:core@1/Text";
import DIDDirectoryHandler "./DIDDirectoryHandler";
import JwtHandler "./JwtHandler";
import Domain "mo:url-kit@3/Domain";
import Runtime "mo:core@1/Runtime";
import Debug "mo:core@1/Debug";
import Iter "mo:core@1/Iter";
import ECDSA "mo:ecdsa@7";
import AtUri "../Types/AtUri";
import ServerInfo "../Types/ServerInfo";

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
    name : Text;
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
    jwtHandler : JwtHandler.Handler,
  ) {
    var sessions = stableData.sessions;
    var accounts = stableData.accounts;
    var nameMap = PureMap.entries(accounts)
    |> Iter.map<(DID.Plc.DID, AccountData), (Text, DID.Plc.DID)>(
      _,
      func((did, account) : (DID.Plc.DID, AccountData)) : (Text, DID.Plc.DID) {
        (account.name, did);
      },
    )
    |> PureMap.fromIter(_, TextX.compareIgnoreCase); // TODO lazy load?

    var emailMap = PureMap.entries(accounts)
    |> Iter.filterMap<(DID.Plc.DID, AccountData), (Text, DID.Plc.DID)>(
      _,
      func((did, account) : (DID.Plc.DID, AccountData)) : ?(Text, DID.Plc.DID) {
        switch (account.email) {
          case (?email) ?(email, did);
          case (null) null;
        };
      },
    )
    |> PureMap.fromIter(_, TextX.compareIgnoreCase); // TODO case sensitivity? TODO lazy load?

    public func get(id : DID.Plc.DID) : ?Account {
      let ?account = PureMap.get(accounts, DIDModule.comparePlcDID, id) else return null;
      ?{
        account with
        id = id;
      };
    };

    public func getByName(name : Text) : ?Account {
      let ?accountId = PureMap.get(nameMap, TextX.compareIgnoreCase, name) else return null;
      get(accountId);
    };

    public func getByEmail(email : Text) : ?Account {
      let ?accountId = PureMap.get(emailMap, TextX.compareIgnoreCase, email) else return null;
      get(accountId);
    };

    public func create(
      request : CreateAccount.Request
    ) : async* Result.Result<CreateAccount.Response, Text> {

      // Validate request
      if (TextX.isEmptyOrWhitespace(request.handle)) return #err("Handle cannot be empty");

      let serverInfo = serverInfoHandler.get();
      let ?name = ServerInfo.getAccountNameFromHandle(serverInfo, request.handle) else return #err("Handle must end with '.{server hostname}'");

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
          let createRequest : DIDDirectoryHandler.CreatePlcRequest = {
            // TODO?
            alsoKnownAs = ["at://" # request.handle];
            // TODO?
            services = [{
              id = "atproto_pds";
              type_ = "AtprotoPersonalDataServer";
              endpoint = "https://" # serverInfo.hostname;
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

      let (newNameMap, nameIsUnique) = PureMap.insert(nameMap, TextX.compareIgnoreCase, name, did);
      if (not nameIsUnique) {
        return #err("Handle is already taken");
      };

      let (newEmailMap, emailIsUnique) = switch (request.email) {
        case (?email) PureMap.insert(emailMap, TextX.compareIgnoreCase, email, did);
        case (null) (emailMap, true);
      };
      if (not emailIsUnique) {
        return #err("Email is already in use");
      };

      let salt = await Random.blob();

      let passwordHash = PBKDF2.pbkdf2_sha512(
        #text(password),
        #blob(salt),
        4096,
        64,
      );

      // Create new account
      let newAccount : Account = {
        id = did;
        name = name;
        email = request.email;
        passwordHash = Blob.fromArray(passwordHash);
        salt = salt;
      };

      // Store the account in stable data
      accounts := PureMap.add(accounts, DIDModule.comparePlcDID, did, newAccount); // TODO how to best handle async failure

      // Update lookup maps
      nameMap := newNameMap;
      emailMap := newEmailMap;

      await* createSessionInternal(newAccount);
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
      let ?account = getAccountFromIdentifier(request.identifier) else return #err("Account not found for identifier: " # request.identifier);

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
        await* createSessionInternal(account),
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
      actorId : DID.Plc.DID
    ) : async* Result.Result<GetSession.Response, Text> {

      // Check if account exists
      let ?account = PureMap.get(
        accounts,
        DIDModule.comparePlcDID,
        actorId,
      ) else return #err("Account not found");

      // Get server info for handle formatting
      let serverInfo = serverInfoHandler.get();

      let publicKey = switch (await* keyHandler.getPublicKey(#verification)) {
        case (#ok(pubKey)) pubKey;
        case (#err(err)) return #err("Failed to get verification public key: " # err);
      };
      let handle = ServerInfo.buildHandleFromAccountName(serverInfo, account.name);
      let alsoKnownAs = [AtUri.toText({ authority = #handle(handle); collection = null })];
      let didDoc = DIDModule.generateDIDDocument(#plc(actorId), alsoKnownAs, publicKey);

      #ok({
        handle = handle;
        did = DID.Plc.toText(actorId);
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

    private func createSessionInternal(account : Account) : async* Result.Result<CreateSessionResponse, Text> {
      let serverInfo = serverInfoHandler.get();
      let serverId : DID.Web.DID = ServerInfo.buildWebDID(serverInfo);

      // Generate session identifiers
      let randomBytes = await Random.blob();
      let (bytesHalf1, bytesHalf2) = IterX.splitAt(randomBytes.vals(), randomBytes.size() / 2);

      let sessionId = "sess_" # BaseX.toBase64(bytesHalf1, #url({ includePadding = false }));
      let refreshTokenId = BaseX.toBase64(bytesHalf2, #url({ includePadding = false }));

      // TODO run in parallel
      let refreshTokenInfo = switch (await* jwtHandler.generateRefreshToken(account.id, serverId)) {
        case (#ok(info)) info;
        case (#err(err)) return #err("Failed to generate refresh token: " # err);
      };
      let accessTokenInfo = switch (await* jwtHandler.generateAccessToken(account.id, serverId, refreshTokenId)) {
        case (#ok(info)) info;
        case (#err(err)) return #err("Failed to generate access token: " # err);
      };

      let refreshTokenHash = SHA256.fromBlob(#sha256, Text.encodeUtf8(refreshTokenInfo.token));

      let now = Time.now();
      // Create new session
      let newSession : Session = {
        did = account.id;
        createdAt = now;
        lastActiveAt = now;
        refreshTokenHash = refreshTokenHash;
        refreshTokenId = refreshTokenId;
        refreshExpiresAt = refreshTokenInfo.expiresAt;
        refreshCount = 0;
        lastRefreshAt = null;
        revoked = null;
      };

      let publicKey = switch (await* keyHandler.getPublicKey(#verification)) {
        case (#ok(pubKey)) pubKey;
        case (#err(err)) return #err("Failed to get verification public key: " # err);
      };

      // Get DID document
      let handle = ServerInfo.buildHandleFromAccountName(serverInfo, account.name);
      let alsoKnownAs = [AtUri.toText({ authority = #handle(handle); collection = null })];
      let didDoc = DIDModule.generateDIDDocument(#plc(account.id), alsoKnownAs, publicKey);

      // Store the session in stable data (using sessionId as key, not token)
      sessions := PureMap.add(sessions, Text.compare, sessionId, newSession);

      // Return response
      #ok({
        accessJwt = accessTokenInfo.token;
        refreshJwt = refreshTokenInfo.token;
        handle = handle;
        did = account.id;
        didDoc = ?didDoc;
      });
    };

    func getAccountFromIdentifier(identifier : Text) : ?Account {
      switch (DID.Plc.fromText(identifier)) {
        case (#ok(did)) {
          let ?account = PureMap.get(
            accounts,
            DIDModule.comparePlcDID,
            did,
          ) else return null;
          ?{
            account with
            id = did;
          };
        };
        case (#err(_)) {
          let serverInfo = serverInfoHandler.get();
          switch (ServerInfo.getAccountNameFromHandle(serverInfo, identifier)) {
            case (?name) getByName(name);
            case (null) getByEmail(identifier); // Fallback to email
          };
        };
      };
    };
  };
};
