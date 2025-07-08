import DID "mo:did";
import CID "mo:cid";
import TID "mo:tid";
import DagCbor "mo:dag-cbor";
import AtUri "../../../../AtUri";
import Json "mo:json";
import Result "mo:new-base/Result";
import Int "mo:new-base/Int";
import JsonSerializer "../../../../../JsonSerializer";
import Array "mo:new-base/Array";

module {

    /// Request type for listing repository records
    public type Request = {
        /// The handle or DID of the repo
        repo : DID.Plc.DID;

        /// The NSID of the record type
        collection : Text;

        /// The number of records to return (1-100, default 50)
        limit : ?Nat;

        /// Pagination cursor
        cursor : ?Text;

        /// Flag to reverse the order of the returned records
        reverse : ?Bool;
    };

    /// Response from a successful list records operation
    public type Response = {
        /// Pagination cursor for next page
        cursor : ?Text;

        /// Array of records matching the query
        records : [ListRecord];
    };

    /// Individual record in a list response
    public type ListRecord = {
        /// AT-URI identifying the record
        uri : AtUri.AtUri;

        /// Content Identifier of the record
        cid : CID.CID;

        /// The record data
        value : DagCbor.Value;
    };

    public func toJson(response : Response) : Json.Json {

        let recordsJson = response.records |> Array.map<ListRecord, Json.Json>(
            _,
            func(record : ListRecord) : Json.Json {
                let atUri = AtUri.toText(record.uri);
                let cidText = CID.toText(record.cid);
                let valueJson = JsonSerializer.fromDagCbor(record.value);

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

    public func fromJson(json : Json.Json) : Result.Result<Request, Text> {

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
};
