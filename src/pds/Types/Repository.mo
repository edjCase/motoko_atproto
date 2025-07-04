import DID "mo:did";
import CID "mo:cid";
import TID "mo:tid";
import Commit "./Commit";

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
        swapCommit : ?Text;
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
        #invalid; // Note: AT Protocol uses "unknown", but "invalid" works too
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
};
