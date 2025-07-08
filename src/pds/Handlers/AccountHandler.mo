import PureMap "mo:new-base/pure/Map";
import DID "mo:did";
import Result "mo:new-base/Result";
import CreateSession "../Types/Lexicons/Com/Atproto/Server/CreateSession";
import CreateAccount "../Types/Lexicons/Com/Atproto/Server/CreateAccount";
import JWT "mo:jwt";
import PBKDF2 "mo:pbkdf2-sha512";
import DIDModule "../DID";
import Time "mo:new-base/Time";
import Random "mo:new-base/Random";
import SHA256 "mo:sha2/Sha256";
import TextX "mo:xtended-text/TextX";
import Blob "mo:base/Blob";
import DIDDocument "../Types/DIDDocument";
import IterTools "mo:itertools/Iter";
import BaseX "mo:base-x-encoder";

module {

    public type StableData = {
        accounts : PureMap.Map<DID.Plc.DID, Account>;
        sessions : PureMap.Map<JWT.Token, Session>;
    };

    public type Session = {
        did : DID.Plc.DID;
        sessionId : Text;
        createdAt : Time.Time;
        lastActiveAt : Time.Time;
        refreshTokenHash : Text; // SHA256 hash of current refresh token
        refreshTokenFamily : Text; // For token rotation detection
        refreshExpiresAt : Time.Time;
        refreshCount : Nat; // Number of times this session has been refreshed
        lastRefreshAt : ?Time.Time; // Optional - null for new sessions
        revoked : ?RevokedInfo; // Optional - null unless revoked
    };

    public type RevokedInfo = {
        time : Time.Time;
        reason : Text; // Reason for revocation
    };

    public type Account = {
        handle : Text;
        email : ?Text;
        passwordHash : Blob;
    };

    public class Handler(stableData : StableData) {

        public func create(
            request : CreateAccount.Request
        ) : Result.Result<CreateAccount.Response, Text> {

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

            if (request.password == null) {
                return #err("Passwordless account creation is not supported yet");
            };

            if (request.recoveryKey != null) {
                // TODO
                return #err("Recovery keys are not supported yet");
            };

            if (request.plcOp != null) {
                // TODO
                return #err("PLC operations are not supported yet");
            };

            // Check if account already exists
            let null = PureMap.get(stableData.accounts, DIDModule.comparePlcDID, request.did) else return #err("Account already exists");

            let salt = await* Random.randomBlob();

            let passwordHash = PBKDF2.pbkdf2_sha512(
                #text(request.password),
                #blob(salt),
                4096,
                64,
            );
            // Create new account
            let newAccount : Account = {
                did = request.did;
                handle = request.handle;
                email = request.email;
                passwordHash = Blob.fromArray(passwordHash);
            };

            // Store the account in stable data
            let updatedAccounts = PureMap.add(stableData.accounts, request.did, newAccount);
            stableData.accounts := updatedAccounts;

            // Return response
            #ok({});
        };

        public func createSession(
            request : CreateSession.Request
        ) : async* Result.Result<CreateSession.Response, Text> {

            // Try parse the identifier as a DID, then email/handle
            let ?(did, account) = getAccountFromIdentifier(request.identifier) else return #err("Account not found for identifier: " # request.identifier);

            // Generate session identifiers
            let randomBytes = await Random.blob();
            let (bytesHalf1, bytesHalf2) = IterTools.splitAt(randomBytes.vals(), randomBytes.size() / 2);

            let sessionId = "sess_" # BaseX.toBase64(bytesHalf1, #url({ includePadding = false }));
            let refreshTokenFamily = "family_" # BaseX.toBase64(bytesHalf2, #url({ includePadding = false }));

            let now = Time.now();
            let refreshExpiresAt = now + (90 * 24 * 60 * 60 * 1_000_000_000); // 90 days in nanoseconds

            // Generate access JWT (short-lived, 1 hour)
            let accessPayload : JWT.Token = {
                header = [
                    ("typ", #string("at+jwt")),
                    ("alg", #string("")), // TODO
                ];
                payload = [
                    ("scope", #string("com.atproto.refresh")),
                    ("sub", #string(DID.Plc.toText(did))),
                    ("aud", #string(bluskyOrOtherPlatformDid)),
                    ("iat", #number(#int(timeInMillis ?))),
                    ("exp", #number(#int(expiresAtMillis ?))),
                ];
            };
            let accessJwt = switch (JWT.sign(accessPayload, signingKey)) {
                case (#ok(token)) token;
                case (#err(msg)) return #err("Failed to create access token: " # msg);
            };

            // Generate refresh JWT (long-lived)
            let refreshPayload : JWT.Token = {
                header = [
                    ("typ", #string("refresh+jwt")),
                    ("alg", #string("")), // TODO
                ];
                payload = [
                    ("scope", #string("com.atproto.refresh")),
                    ("sub", #string(DID.Plc.toText(did))),
                    ("aud", #string(bluskyOrOtherPlatformDid)),
                    ("jti", #string(???)),
                    ("iat", #number(#int(timeInMillis ?))),
                    ("exp", #number(#int(refreshExpiresAtMillis ?))),
                ];
            };
            let refreshJwt = switch (JWT.sign(refreshPayload, signingKey)) {
                case (#ok(token)) token;
                case (#err(msg)) return #err("Failed to create refresh token: " # msg);
            };

            let refreshTokenHash = SHA256.hash(refreshToken);
            // Create new session
            let newSession : Session = {
                did = did;
                sessionId = sessionId;
                createdAt = now;
                lastActiveAt = now;
                refreshTokenHash = refreshTokenHash;
                refreshTokenFamily = refreshTokenFamily;
                refreshExpiresAt = refreshExpiresAt;
                refreshCount = 0;
                lastRefreshAt = null;
                revoked = false;
                revokedAt = null;
                revokedReason = null;
            };

            // Get DID document
            let didDoc = switch (DID.resolve(did)) {
                case (#ok(doc)) doc;
                case (#err(_)) return #err("Failed to resolve DID document");
            };

            // Store the session in stable data (using sessionId as key, not token)
            stableData.sessions := PureMap.add(stableData.sessions, sessionId, newSession);

            // Return response
            #ok({
                accessJwt = accessJwt;
                refreshJwt = refreshJwt;
                handle = account.handle;
                did = did;
                didDoc = ?didDoc;
                email = account.email;
                emailConfirmed = null; // TODO: Implement email confirmation
                emailAuthFactor = null; // TODO: Implement email authentication factor
                active = null; // TODO: Implement active flag
                status = null; // TODO: Implement status description
            });
        };

        func getAccountFromIdentifier(identifier : Text) : ?(DID.Plc.DID, Account) {
            switch (DID.Plc.fromText(identifier)) {
                case (#ok(did)) {
                    let ?account = PureMap.get(
                        stableData.accounts,
                        DIDModule.comparePlcDID,
                        did,
                    ) else return null;
                    ?(did, account);
                };
                case (#err(_)) {
                    label f for ((did, acc) in PureMap.entries(stableData.accounts)) {
                        if (acc.handle == identifier or acc.email == ?identifier) {
                            return ?(did, acc);
                        };
                    };
                    null;
                };
            };
        };
    };
};
