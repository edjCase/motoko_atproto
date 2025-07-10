import DID "mo:did";
import CID "mo:cid";
import DagCbor "mo:dag-cbor";
import AtUri "../../../../AtUri";
import Json "mo:json";
import Result "mo:new-base/Result";
import Array "mo:base/Array";
import JsonDagCborMapper "../../../../../JsonDagCborMapper";
import Common "./Common";

module {

    public type WriteOperation = {
        #create : CreateOp;
        #update : UpdateOp;
        #delete : DeleteOp;
    };

    public type CreateOp = {
        collection : Text;
        rkey : ?Text;
        value : DagCbor.Value;
    };

    public type UpdateOp = {
        collection : Text;
        rkey : Text;
        value : DagCbor.Value;
    };

    public type DeleteOp = {
        collection : Text;
        rkey : Text;
    };

    public type Request = {
        repo : DID.Plc.DID;
        validate : ?Bool;
        writes : [WriteOperation];
        swapCommit : ?CID.CID;
    };

    public type WriteResult = {
        #create : CreateResult;
        #update : UpdateResult;
        #delete : DeleteResult;
    };

    public type CreateResult = {
        uri : AtUri.AtUri;
        cid : CID.CID;
        validationStatus : Common.ValidationStatus;
    };

    public type UpdateResult = {
        uri : AtUri.AtUri;
        cid : CID.CID;
        validationStatus : Common.ValidationStatus;
    };

    public type DeleteResult = {};

    public type Response = {
        commit : ?Common.CommitMeta;
        results : [WriteResult];
    };

    public type Error = {
        #invalidSwap : { message : Text };
    };

    public func toJson(response : Response) : Json.Json {
        let commitJson = switch (response.commit) {
            case (?commit) #object_([
                ("cid", #string(CID.toText(commit.cid))),
                ("rev", #string(commit.rev)),
            ]);
            case (null) #null_;
        };

        let resultsJson = response.results |> Array.map<WriteResult, Json.Json>(
            _,
            func(result) {
                switch (result) {
                    case (#create(cr)) #object_([
                        ("uri", #string(AtUri.toText(cr.uri))),
                        ("cid", #string(CID.toText(cr.cid))),
                        (
                            "validationStatus",
                            #string(
                                switch (cr.validationStatus) {
                                    case (#valid) "valid";
                                    case (#unknown) "unknown";
                                }
                            ),
                        ),
                    ]);
                    case (#update(ur)) #object_([
                        ("uri", #string(AtUri.toText(ur.uri))),
                        ("cid", #string(CID.toText(ur.cid))),
                        (
                            "validationStatus",
                            #string(
                                switch (ur.validationStatus) {
                                    case (#valid) "valid";
                                    case (#unknown) "unknown";
                                }
                            ),
                        ),
                    ]);
                    case (#delete(_)) #object_([]);
                };
            },
        );

        #object_([
            ("commit", commitJson),
            ("results", #array(resultsJson)),
        ]);
    };

    public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
        let repoText = switch (Json.getAsText(json, "repo")) {
            case (#ok(repo)) repo;
            case (#err(#pathNotFound)) return #err("Missing required field: repo");
            case (#err(#typeMismatch)) return #err("Invalid repo field, expected string");
        };

        let repo = switch (DID.Plc.fromText(repoText)) {
            case (#ok(did)) did;
            case (#err(e)) return #err("Invalid repo DID: " # e);
        };

        let validate = switch (Json.getAsBool(json, "validate")) {
            case (#ok(v)) ?v;
            case (#err(#pathNotFound)) null;
            case (#err(#typeMismatch)) return #err("Invalid validate field, expected boolean");
        };

        let writesArray = switch (Json.getAsArray(json, "writes")) {
            case (#ok(arr)) arr;
            case (#err(#pathNotFound)) return #err("Missing required field: writes");
            case (#err(#typeMismatch)) return #err("Invalid writes field, expected array");
        };

        // TODO: Parse writes array - complex union type parsing needed

        let swapCommit = switch (Json.getAsText(json, "swapCommit")) {
            case (#ok(s)) switch (CID.fromText(s)) {
                case (#ok(cid)) ?cid;
                case (#err(e)) return #err("Invalid swapCommit CID: " # e);
            };
            case (#err(#pathNotFound)) null;
            case (#err(#typeMismatch)) return #err("Invalid swapCommit field, expected string");
        };

        #ok({
            repo = repo;
            validate = validate;
            writes = []; // TODO: Implement write operation parsing
            swapCommit = swapCommit;
        });
    };

};
