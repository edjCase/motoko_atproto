import CID "mo:cid";
import Json "mo:json";

module {

    /// A URI with a content-hash fingerprint.
    public type StrongRef = {
        /// Link to the resource
        uri : AtUri.AtUri;
        /// CID reference
        cid : CID.CID;
    };
};
