import Text "mo:base/Text";
import Iter "mo:base/Iter";
import HashMap "mo:base/HashMap";
import Result "mo:base/Result";
import Liminal "mo:liminal";
import App "mo:liminal/App";
import Router "mo:liminal/Router";
import Debug "mo:new-base/Debug";
import RepositoryHandler "Handlers/RepositoryHandler";
import ServerInfoHandler "Handlers/ServerInfoHandler";
import KeyHandler "Handlers/KeyHandler";
import ServerInfo "Types/ServerInfo";
import Error "mo:new-base/Error";
import Array "mo:new-base/Array";
import Blob "mo:new-base/Blob";
import Sha256 "mo:sha2/Sha256";
import Json "mo:json";
import BaseX "mo:base-x-encoder";
import TextX "mo:xtended-text/TextX";
import DIDModule "./DID";
import DagCbor "mo:dag-cbor";
import CID "mo:cid";
import Repository "Types/Repository";
import DID "mo:did";
import TID "mo:tid";
import Int "mo:new-base/Int";
import AtUri "Types/AtUri";

module {

    public func toDagCbor(value : Json.Json) : DagCbor.Value {
        // Convert JSON value to DagCbor
        switch (value) {
            case (#null_) #null_;
            case (#bool(b)) #bool(b);
            case (#number(#int(n))) #int(n);
            case (#number(#float(f))) #float(f);
            case (#string(s)) #text(s);
            case (#array(arr)) #array(arr |> Array.map(_, toDagCbor));
            case (#object_(obj)) #map(
                obj |> Array.map<(Text, Json.Json), (Text, DagCbor.Value)>(
                    _,
                    func(pair : (Text, Json.Json)) : (Text, DagCbor.Value) {
                        let key = pair.0;
                        let value = toDagCbor(pair.1);
                        (key, value);
                    },
                )
            );
        };
    };

    public func fromDagCbor(value : DagCbor.Value) : Json.Json {
        // Convert DagCbor value to JSON
        switch (value) {
            case (#null_) #null_;
            case (#bool(b)) #bool(b);
            case (#int(i)) #number(#int(i));
            case (#float(f)) #number(#float(f));
            case (#text(t)) #string(t);
            case (#bytes(b)) #string(BaseX.toBase64(b.vals(), #url({ includePadding = false })));
            case (#array(arr)) #array(arr |> Array.map(_, fromDagCbor));
            case (#map(m)) #object_(
                m |> Array.map<(Text, DagCbor.Value), (Text, Json.Json)>(
                    _,
                    func(pair : (Text, DagCbor.Value)) : (Text, Json.Json) {
                        let key = pair.0;
                        let value = fromDagCbor(pair.1);
                        (key, value);
                    },
                )
            );
            case (#cid(cid)) #string(CID.toText(cid));
        };
    };

    public func toDescribeRepoRequest(
        json : Json.Json
    ) : Result.Result<Repository.DescribeRepoRequest, Text> {

        // Extract required fields

        let repoText = switch (Json.getAsText(json, "repo")) {
            case (#ok(repo)) repo;
            case (#err(#pathNotFound)) return #err("Missing required field: repo");
            case (#err(#typeMismatch)) return #err("Invalid repo field, expected string");
        };
        let repo = switch (DID.Plc.fromText(repoText)) {
            case (#ok(did)) did;
            case (#err(e)) return #err("Invalid repo DID: " # e);
        };

        #ok({
            repo = repo;
        });
    };

    public func fromDescribeRepoResponse(
        response : Repository.DescribeRepoResponse
    ) : Json.Json {

        let didText = DID.Plc.toText(response.did);
        let didDocJson = fromDidDocument(response.didDoc);
        let collectionsJson = response.collections |> Array.map<Text, Json.Json>(
            _,
            func(collection : Text) : Json.Json = #string(collection),
        );

        #object_([
            ("handle", #string(response.handle)),
            ("did", #string(didText)),
            ("didDoc", didDocJson),
            ("collections", #array(collectionsJson)),
            ("handleIsCorrect", #bool(response.handleIsCorrect)),
        ]);
    };

    public func fromDidDocument(didDoc : DIDModule.DidDocument) : Json.Json {

        let verificationMethodsJson = didDoc.verificationMethod
        |> Array.map<DIDModule.VerificationMethod, Json.Json>(
            _,
            func(vm : DIDModule.VerificationMethod) : Json.Json = #object_([
                ("id", #string(vm.id)),
                ("type", #string(vm.type_)),
                ("controller", #string(DID.toText(vm.controller))),
                (
                    "publicKeyMultibase",
                    switch (vm.publicKeyMultibase) {
                        case (null) #null_;
                        case (?publicKey) #string(DID.Key.toText(publicKey, #base58btc));
                    },
                ),
            ]),
        );

        let textArrayToJson = func(texts : [Text]) : Json.Json {
            #array(texts |> Array.map<Text, Json.Json>(_, func(text : Text) : Json.Json = #string(text)));
        };

        #object_([
            ("id", #string(DID.toText(didDoc.id))),
            ("context", textArrayToJson(didDoc.context)),
            ("alsoKnownAs", textArrayToJson(didDoc.alsoKnownAs)),
            ("verificationMethod", #array(verificationMethodsJson)),
            ("authentication", textArrayToJson(didDoc.authentication)),
            ("assertionMethod", textArrayToJson(didDoc.assertionMethod)),
        ]);
    };

    public func toPutRecordRequest(
        json : Json.Json
    ) : Result.Result<Repository.PutRecordRequest, Text> {

        // Extract required fields

        let repoText = switch (Json.getAsText(json, "repo")) {
            case (#ok(repo)) repo;
            case (#err(#pathNotFound)) return #err("Missing required field: repo");
            case (#err(#typeMismatch)) return #err("Invalid repo field, expected string");
        };
        let repo = switch (DID.Plc.fromText(repoText)) {
            case (#ok(did)) did;
            case (#err(e)) return #err("Invalid repo DID: " # e);
        };

        let collection = switch (Json.getAsText(json, "collection")) {
            case (#ok(collection)) collection;
            case (#err(#pathNotFound)) return #err("Missing required field: collection");
            case (#err(#typeMismatch)) return #err("Invalid collection field, expected string");
        };

        let rkey = switch (Json.getAsText(json, "rkey")) {
            case (#ok(rkey)) rkey;
            case (#err(#pathNotFound)) return #err("Missing required field: rkey");
            case (#err(#typeMismatch)) return #err("Invalid rkey field, expected string");
        };

        let recordJson = switch (Json.get(json, "record")) {
            case (?record) record;
            case (null) return #err("Missing required field: record");
        };

        let recordDagCbor = toDagCbor(recordJson);

        // Extract optional fields

        let validate = switch (Json.getAsBool(json, "validate")) {
            case (#ok(validate)) ?validate;
            case (#err(#pathNotFound)) null;
            case (#err(#typeMismatch)) return #err("Invalid validate field, expected boolean");
        };

        let swapRecord = switch (Json.getAsText(json, "swapRecord")) {
            case (#ok(s)) switch (CID.fromText(s)) {
                case (#ok(cid)) ?cid;
                case (#err(e)) return #err("Invalid swapRecord CID: " # e);
            };
            case (#err(#pathNotFound)) null;
            case (#err(#typeMismatch)) return #err("Invalid swapRecord field, expected string");
        };

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
            collection = collection;
            rkey = rkey;
            validate = validate;
            record = recordDagCbor;
            swapRecord = swapRecord;
            swapCommit = swapCommit;
        });
    };

    public func toCreateRecordRequest(
        json : Json.Json
    ) : Result.Result<Repository.CreateRecordRequest, Text> {

        // Extract required fields

        let repoText = switch (Json.getAsText(json, "repo")) {
            case (#ok(repo)) repo;
            case (#err(#pathNotFound)) return #err("Missing required field: repo");
            case (#err(#typeMismatch)) return #err("Invalid repo field, expected string");
        };
        let repo = switch (DID.Plc.fromText(repoText)) {
            case (#ok(did)) did;
            case (#err(e)) return #err("Invalid repo DID: " # e);
        };

        let collection = switch (Json.getAsText(json, "collection")) {
            case (#ok(collection)) collection;
            case (#err(#pathNotFound)) return #err("Missing required field: collection");
            case (#err(#typeMismatch)) return #err("Invalid collection field, expected string");
        };

        let recordJson = switch (Json.get(json, "record")) {
            case (?record) record;
            case (null) return #err("Missing required field: record");
        };

        let recordDagCbor = toDagCbor(recordJson);

        // Extract optional fields

        let rkey = switch (Json.getAsText(json, "rkey")) {
            case (#ok(rkey)) ?rkey;
            case (#err(#pathNotFound)) null;
            case (#err(#typeMismatch)) return #err("Invalid rkey field, expected string");
        };

        let validate = switch (Json.getAsBool(json, "validate")) {
            case (#ok(validate)) ?validate;
            case (#err(#pathNotFound)) null;
            case (#err(#typeMismatch)) return #err("Invalid validate field, expected boolean");
        };

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
            collection = collection;
            rkey = rkey;
            record = recordDagCbor;
            validate = validate;
            swapCommit = swapCommit;
        });
    };

    public func toDeleteRecordRequest(
        json : Json.Json
    ) : Result.Result<Repository.DeleteRecordRequest, Text> {

        // Extract required fields

        let repoText = switch (Json.getAsText(json, "repo")) {
            case (#ok(repo)) repo;
            case (#err(#pathNotFound)) return #err("Missing required field: repo");
            case (#err(#typeMismatch)) return #err("Invalid repo field, expected string");
        };
        let repo = switch (DID.Plc.fromText(repoText)) {
            case (#ok(did)) did;
            case (#err(e)) return #err("Invalid repo DID: " # e);
        };

        let collection = switch (Json.getAsText(json, "collection")) {
            case (#ok(collection)) collection;
            case (#err(#pathNotFound)) return #err("Missing required field: collection");
            case (#err(#typeMismatch)) return #err("Invalid collection field, expected string");
        };

        let rkey = switch (Json.getAsText(json, "rkey")) {
            case (#ok(rkey)) rkey;
            case (#err(#pathNotFound)) return #err("Missing required field: rkey");
            case (#err(#typeMismatch)) return #err("Invalid rkey field, expected string");
        };

        // Extract optional fields

        let swapRecord = switch (Json.getAsText(json, "swapRecord")) {
            case (#ok(s)) switch (CID.fromText(s)) {
                case (#ok(cid)) ?cid;
                case (#err(e)) return #err("Invalid swapRecord CID: " # e);
            };
            case (#err(#pathNotFound)) null;
            case (#err(#typeMismatch)) return #err("Invalid swapRecord field, expected string");
        };

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
            collection = collection;
            rkey = rkey;
            swapRecord = swapRecord;
            swapCommit = swapCommit;
        });
    };

    public func toGetRecordRequest(
        json : Json.Json
    ) : Result.Result<Repository.GetRecordRequest, Text> {

        // Extract required fields

        let repoText = switch (Json.getAsText(json, "repo")) {
            case (#ok(repo)) repo;
            case (#err(#pathNotFound)) return #err("Missing required field: repo");
            case (#err(#typeMismatch)) return #err("Invalid repo field, expected string");
        };
        let repo = switch (DID.Plc.fromText(repoText)) {
            case (#ok(did)) did;
            case (#err(e)) return #err("Invalid repo DID: " # e);
        };

        let collection = switch (Json.getAsText(json, "collection")) {
            case (#ok(collection)) collection;
            case (#err(#pathNotFound)) return #err("Missing required field: collection");
            case (#err(#typeMismatch)) return #err("Invalid collection field, expected string");
        };

        let rkey = switch (Json.getAsText(json, "rkey")) {
            case (#ok(rkey)) rkey;
            case (#err(#pathNotFound)) return #err("Missing required field: rkey");
            case (#err(#typeMismatch)) return #err("Invalid rkey field, expected string");
        };

        // Extract optional fields

        let cid = switch (Json.getAsText(json, "cid")) {
            case (#ok(s)) switch (CID.fromText(s)) {
                case (#ok(cid)) ?cid;
                case (#err(e)) return #err("Invalid cid: " # e);
            };
            case (#err(#pathNotFound)) null;
            case (#err(#typeMismatch)) return #err("Invalid cid field, expected string");
        };

        #ok({
            repo = repo;
            collection = collection;
            rkey = rkey;
            cid = cid;
        });
    };

    public func toListRecordsRequest(
        json : Json.Json
    ) : Result.Result<Repository.ListRecordsRequest, Text> {

        // Extract required fields

        let repoText = switch (Json.getAsText(json, "repo")) {
            case (#ok(repo)) repo;
            case (#err(#pathNotFound)) return #err("Missing required field: repo");
            case (#err(#typeMismatch)) return #err("Invalid repo field, expected string");
        };
        let repo = switch (DID.Plc.fromText(repoText)) {
            case (#ok(did)) did;
            case (#err(e)) return #err("Invalid repo DID: " # e);
        };

        let collection = switch (Json.getAsText(json, "collection")) {
            case (#ok(collection)) collection;
            case (#err(#pathNotFound)) return #err("Missing required field: collection");
            case (#err(#typeMismatch)) return #err("Invalid collection field, expected string");
        };

        // Extract optional fields

        let limit = switch (Json.getAsInt(json, "limit")) {
            case (#ok(limit)) {
                if (limit < 1 or limit > 100) {
                    return #err("Invalid limit: must be between 1 and 100");
                };
                ?Int.abs(limit);
            };
            case (#err(#pathNotFound)) null;
            case (#err(#typeMismatch)) return #err("Invalid limit field, expected integer");
        };

        let cursor = switch (Json.getAsText(json, "cursor")) {
            case (#ok(cursor)) ?cursor;
            case (#err(#pathNotFound)) null;
            case (#err(#typeMismatch)) return #err("Invalid cursor field, expected string");
        };

        let reverse = switch (Json.getAsBool(json, "reverse")) {
            case (#ok(reverse)) ?reverse;
            case (#err(#pathNotFound)) null;
            case (#err(#typeMismatch)) return #err("Invalid reverse field, expected boolean");
        };

        #ok({
            repo = repo;
            collection = collection;
            limit = limit;
            cursor = cursor;
            reverse = reverse;
        });
    };

    public func fromGetRecordResponse(
        response : Repository.GetRecordResponse
    ) : Json.Json {

        let atUri = AtUri.toText(response.uri);
        let valueJson = fromDagCbor(response.value);
        #object_([
            ("uri", #string(atUri)),
            (
                "cid",
                switch (response.cid) {
                    case (?cid) #string(CID.toText(cid));
                    case (null) #null_;
                },
            ),
            ("value", valueJson),
        ]);
    };

    public func fromCreateRecordResponse(
        response : Repository.CreateRecordResponse
    ) : Json.Json {

        let atUri = AtUri.toText(response.uri);
        let cidText = CID.toText(response.cid);

        let validationStatusText = switch (response.validationStatus) {
            case (#valid) "valid";
            case (#unknown) "unknown";
        };

        #object_([
            ("uri", #string(atUri)),
            ("cid", #string(cidText)),
            (
                "commit",
                switch (response.commit) {
                    case (?commit) #object_([
                        ("cid", #string(CID.toText(commit.cid))),
                        ("rev", #string(TID.toText(commit.rev))),
                    ]);
                    case (null) #null_;
                },
            ),
            ("validationStatus", #string(validationStatusText)),
        ]);
    };

    public func fromDeleteRecordResponse(
        response : Repository.DeleteRecordResponse
    ) : Json.Json {

        #object_([
            (
                "commit",
                switch (response.commit) {
                    case (?commit) #object_([
                        ("cid", #string(CID.toText(commit.cid))),
                        ("rev", #string(TID.toText(commit.rev))),
                    ]);
                    case (null) #null_;
                },
            ),
        ]);
    };

    public func fromPutRecordResponse(
        response : Repository.PutRecordResponse
    ) : Json.Json {

        let atUri = AtUri.toText(response.uri);
        let cidText = CID.toText(response.cid);

        #object_([
            ("uri", #string(atUri)),
            ("cid", #string(cidText)),
            (
                "commit",
                switch (response.commit) {
                    case (?commit) #object_([
                        ("cid", #string(CID.toText(commit.cid))),
                        ("rev", #string(TID.toText(commit.rev))),
                    ]);
                    case (null) #null_;
                },
            ),
            (
                "validationStatus",
                switch (response.validationStatus) {
                    case (?status) switch (status) {
                        case (#valid) #string("valid");
                        case (#unknown) #string("unknown");
                    };
                    case (null) #null_;
                },
            ),
        ]);
    };

    public func fromListRecordsResponse(
        response : Repository.ListRecordsResponse
    ) : Json.Json {

        let recordsJson = response.records |> Array.map<Repository.ListRecord, Json.Json>(
            _,
            func(record : Repository.ListRecord) : Json.Json {
                let atUri = AtUri.toText(record.uri);
                let cidText = CID.toText(record.cid);
                let valueJson = fromDagCbor(record.value);

                #object_([
                    ("uri", #string(atUri)),
                    ("cid", #string(cidText)),
                    ("value", valueJson),
                ]);
            },
        );

        #object_([
            (
                "cursor",
                switch (response.cursor) {
                    case (?cursor) #string(cursor);
                    case (null) #null_;
                },
            ),
            ("records", #array(recordsJson)),
        ]);
    };

    public func fromSignedPlcRequest(request : DIDModule.SignedPlcRequest) : Json.Json {
        func toTextArray(arr : [Text]) : [Json.Json] {
            arr |> Array.map(_, func(item : Text) : Json.Json = #string(item));
        };

        let verificationMethodsJsonObj : Json.Json = #object_(
            request.verificationMethods
            |> Array.map<(Text, Text), (Text, Json.Json)>(
                _,
                func(pair : (Text, Text)) : (Text, Json.Json) = (pair.0, #string(pair.1)),
            )
        );

        let servicesJsonObj : Json.Json = #object_(
            request.services
            |> Array.map<DIDModule.PlcService, (Text, Json.Json)>(
                _,
                func(service : DIDModule.PlcService) : (Text, Json.Json) = (
                    service.name,
                    #object_([
                        ("type", #string(service.type_)),
                        ("endpoint", #string(service.endpoint)),
                    ]),
                ),
            )
        );

        #object_([
            ("type", #string(request.type_)),
            ("rotationKeys", #array(request.rotationKeys |> toTextArray(_))),
            ("verificationMethods", verificationMethodsJsonObj),
            ("alsoKnownAs", #array(request.alsoKnownAs |> toTextArray(_))),
            ("services", servicesJsonObj),
            (
                "prev",
                switch (request.prev) {
                    case (?prev) #string(prev);
                    case (null) #null_;
                },
            ),
            ("sig", #string(BaseX.toBase64(request.signature.vals(), #url({ includePadding = false })))),
        ]);
    };
};
