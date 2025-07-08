import DID "mo:did";
import Json "mo:json";
import Result "mo:new-base/Result";
import DIDDocument "../../../../DIDDocument";
import DagCbor "mo:dag-cbor";
import JsonDagCborMapper "../../../../../JsonDagCborMapper";

module {

    /// Request type for creating an account
    public type Request = {
        /// Requested handle for the account
        handle : Text;

        /// Optional email address
        email : ?Text;

        /// Optional pre-existing atproto DID, being imported to a new account
        did : ?DID.Plc.DID;

        /// Optional invite code
        inviteCode : ?Text;

        /// Optional verification code
        verificationCode : ?Text;

        /// Optional verification phone number
        verificationPhone : ?Text;

        /// Optional initial account password
        password : ?Text;

        /// Optional DID PLC rotation key (aka, recovery key) to be included in PLC creation operation
        recoveryKey : ?Text;

        /// Optional signed DID PLC operation to be submitted as part of importing an existing account
        plcOp : ?DagCbor.Value;
    };

    /// Response from successful account creation (account login session)
    public type Response = {
        /// Access JWT token
        accessJwt : Text;

        /// Refresh JWT token
        refreshJwt : Text;

        /// Handle of the new account
        handle : Text;

        /// The DID of the new account
        did : DID.Plc.DID;

        /// Optional complete DID document
        didDoc : ?DIDDocument.DIDDocument;
    };

    public func toJson(response : Response) : Json.Json {

        let didText = DID.Plc.toText(response.did);

        let didDocJson = switch (response.didDoc) {
            case (?didDoc) DIDDocument.toJson(didDoc);
            case (null) #null_;
        };

        #object_([
            ("accessJwt", #string(response.accessJwt)),
            ("refreshJwt", #string(response.refreshJwt)),
            ("handle", #string(response.handle)),
            ("did", #string(didText)),
            ("didDoc", didDocJson),
        ]);
    };

    public func fromJson(json : Json.Json) : Result.Result<Request, Text> {

        // Extract required fields

        let handle = switch (Json.getAsText(json, "handle")) {
            case (#ok(handle)) handle;
            case (#err(#pathNotFound)) return #err("Missing required field: handle");
            case (#err(#typeMismatch)) return #err("Invalid handle field, expected string");
        };

        // Extract optional fields

        let email = switch (Json.getAsText(json, "email")) {
            case (#ok(email)) ?email;
            case (#err(#pathNotFound)) null;
            case (#err(#typeMismatch)) return #err("Invalid email field, expected string");
        };

        let did = switch (Json.getAsText(json, "did")) {
            case (#ok(didText)) switch (DID.Plc.fromText(didText)) {
                case (#ok(did)) ?did;
                case (#err(e)) return #err("Invalid DID: " # e);
            };
            case (#err(#pathNotFound)) null;
            case (#err(#typeMismatch)) return #err("Invalid did field, expected string");
        };

        let inviteCode = switch (Json.getAsText(json, "inviteCode")) {
            case (#ok(code)) ?code;
            case (#err(#pathNotFound)) null;
            case (#err(#typeMismatch)) return #err("Invalid inviteCode field, expected string");
        };

        let verificationCode = switch (Json.getAsText(json, "verificationCode")) {
            case (#ok(code)) ?code;
            case (#err(#pathNotFound)) null;
            case (#err(#typeMismatch)) return #err("Invalid verificationCode field, expected string");
        };

        let verificationPhone = switch (Json.getAsText(json, "verificationPhone")) {
            case (#ok(phone)) ?phone;
            case (#err(#pathNotFound)) null;
            case (#err(#typeMismatch)) return #err("Invalid verificationPhone field, expected string");
        };

        let password = switch (Json.getAsText(json, "password")) {
            case (#ok(password)) ?password;
            case (#err(#pathNotFound)) null;
            case (#err(#typeMismatch)) return #err("Invalid password field, expected string");
        };

        let recoveryKey = switch (Json.getAsText(json, "recoveryKey")) {
            case (#ok(key)) ?key;
            case (#err(#pathNotFound)) null;
            case (#err(#typeMismatch)) return #err("Invalid recoveryKey field, expected string");
        };

        let plcOp = switch (Json.get(json, "plcOp")) {
            case (?plcOpJson) ?JsonDagCborMapper.toDagCbor(plcOpJson);
            case (null) null;
        };

        #ok({
            handle = handle;
            email = email;
            did = did;
            inviteCode = inviteCode;
            verificationCode = verificationCode;
            verificationPhone = verificationPhone;
            password = password;
            recoveryKey = recoveryKey;
            plcOp = plcOp;
        });
    };
};
