import DID "mo:did";
import CID "mo:cid";
import TID "mo:tid";
import DagCbor "mo:dag-cbor";
import AtUri "./AtUri";
import DIDModule "../DID"

module {

    public type RepositoryWithoutDID = {
        head : CID.CID; // CID of current commit
        rev : TID.TID; // TID timestamp
        active : Bool;
        status : ?Text; // Optional status if not active
    };

    public type Repository = RepositoryWithoutDID and {
        did : DID.Plc.DID;
    };

    /// Metadata about a repository commit
    public type CommitMeta = {
        /// Content Identifier representing the commit
        cid : CID.CID;

        /// Timestamp Identifier representing the revision/version
        rev : TID.TID;
    };

    /// Validation status of the created record
    public type ValidationStatus = {
        /// Record passed Lexicon schema validation
        #valid;

        /// Record validation status unknown (for unrecognized schemas)
        #unknown;
    };

    /// Request type for describing a repository
    public type DescribeRepoRequest = {
        /// The handle or DID of the repo
        repo : DID.Plc.DID;
    };

    /// Response from a successful describe repo operation
    public type DescribeRepoResponse = {
        /// The handle for this account
        handle : Text;

        /// The DID for this account
        did : DID.Plc.DID;

        /// The complete DID document for this account
        didDoc : DIDModule.DidDocument;

        /// List of all the collections (NSIDs) for which this repo contains at least one record
        collections : [Text];

        /// Indicates if handle is currently valid (resolves bi-directionally)
        handleIsCorrect : Bool;
    };

    /// Request type for creating a single new repository record
    public type CreateRecordRequest = {
        /// The handle or DID of the repo (aka, current account)
        repo : DID.Plc.DID;

        /// The NSID of the record collection (e.g., "app.bsky.feed.post")
        collection : Text;

        /// The Record Key. Optional - if not provided, system will generate one.
        /// Maximum length: 512 characters
        rkey : ?Text;

        /// The record itself. Must contain a $type field that matches the collection NSID
        record : DagCbor.Value;

        /// Schema validation setting:
        /// - true: require Lexicon schema validation
        /// - false: skip Lexicon schema validation
        /// - null: validate only for known Lexicons (default behavior)
        validate : ?Bool;

        /// Compare and swap with the previous commit by CID.
        /// Used for atomic updates - operation fails if repo state has changed
        swapCommit : ?CID.CID;
    };

    /// Response from a successful record creation
    public type CreateRecordResponse = {
        /// AT-URI identifying the created record
        uri : AtUri.AtUri;

        /// Content Identifier of the created record
        cid : CID.CID;

        /// Optional metadata about the repository commit that included this record
        commit : ?CommitMeta;

        /// Validation status of the created record against its Lexicon schema
        validationStatus : ValidationStatus;
    };

    /// Request type for deleting a repository record
    public type DeleteRecordRequest = {
        /// The handle or DID of the repo (aka, current account)
        repo : DID.Plc.DID;

        /// The NSID of the record collection
        collection : Text;

        /// The Record Key
        rkey : Text;

        /// Compare and swap with the previous record by CID
        swapRecord : ?CID.CID;

        /// Compare and swap with the previous commit by CID
        swapCommit : ?CID.CID;
    };

    /// Response from a successful record deletion
    public type DeleteRecordResponse = {
        /// Optional metadata about the repository commit that included this deletion
        commit : ?CommitMeta;
    };

    /// Request type for getting a single repository record
    public type GetRecordRequest = {
        /// The handle or DID of the repo
        repo : DID.Plc.DID;

        /// The NSID of the record collection
        collection : Text;

        /// The Record Key
        rkey : Text;

        /// The CID of the version of the record. If not provided, returns the most recent version
        cid : ?CID.CID;
    };

    /// Response from a successful record retrieval
    public type GetRecordResponse = {
        /// AT-URI identifying the retrieved record
        uri : AtUri.AtUri;

        /// Content Identifier of the retrieved record
        cid : ?CID.CID;

        /// The record data
        value : DagCbor.Value;
    };

    /// Request type for creating or updating a repository record
    public type PutRecordRequest = {
        /// The handle or DID of the repo (aka, current account)
        repo : DID.Plc.DID;

        /// The NSID of the record collection
        collection : Text;

        /// The Record Key. Maximum length: 512 characters
        rkey : Text;

        /// Schema validation setting:
        /// - true: require Lexicon schema validation
        /// - false: skip Lexicon schema validation
        /// - null: validate only for known Lexicons (default behavior)
        validate : ?Bool;

        /// The record to write
        record : DagCbor.Value;

        /// Compare and swap with the previous record by CID
        swapRecord : ?CID.CID;

        /// Compare and swap with the previous commit by CID
        swapCommit : ?CID.CID;
    };

    /// Response from a successful record put operation
    public type PutRecordResponse = {
        /// AT-URI identifying the record
        uri : AtUri.AtUri;

        /// Content Identifier of the record
        cid : CID.CID;

        /// Optional metadata about the repository commit that included this record
        commit : ?CommitMeta;

        /// Validation status of the record against its Lexicon schema
        validationStatus : ?ValidationStatus;
    };

    /// Request type for listing repository records
    public type ListRecordsRequest = {
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

    /// Individual record in a list response
    public type ListRecord = {
        /// AT-URI identifying the record
        uri : AtUri.AtUri;

        /// Content Identifier of the record
        cid : CID.CID;

        /// The record data
        value : DagCbor.Value;
    };

    /// Response from a successful list records operation
    public type ListRecordsResponse = {
        /// Pagination cursor for next page
        cursor : ?Text;

        /// Array of records matching the query
        records : [ListRecord];
    };
};
