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

    public func toPutRecordRequest(
        json : Json.Json
    ) : ?DIDModule.PutRecordRequest {
        let #object_(obj) = json else return null;
        // Helper function to get a field from the object
        func getField(name : Text) : ?Json.Json {
            switch (Array.find<(Text, Json.Json)>(obj, func(pair) = pair.0 == name)) {
                case (?pair) ?pair.1;
                case (null) null;
            };
        };

        // Extract required fields
        let ?#string(repo) = getField("repo") else return null;

        let ?#string(collection) = getField("collection") else return null;

        let ?#string(rkey) = getField("rkey") else return null;

        let ?record = getField("record") else return null;
        let recordDagCbor = switch (DagCbor.fromJson(record)) {
            case (#ok(dagCbor)) dagCbor;
            case (#err(e)) return null; // Invalid DagCbor
        };

        let value = switch (getField("validate")) {
            case (?v) v;
            case (null) return #err("Missing required field: validate");
        };

        // Extract optional fields
        let validate = switch (getBooleanField("validate")) {
            case (#ok(v)) v;
            case (#err(e)) return #err(e);
        };

        let swapRecord = switch (getStringField("swapRecord")) {
            case (#ok(s)) s;
            case (#err(e)) return #err(e);
        };

        let swapCommit = switch (getStringField("swapCommit")) {
            case (#ok(s)) s;
            case (#err(e)) return #err(e);
        };

        #ok({
            repo = repo;
            collection = collection;
            rkey = rkey;
            validate = validate;
            record = record;
            swapRecord = swapRecord;
            swapCommit = swapCommit;
        });
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
