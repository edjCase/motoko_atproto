import DID "mo:did";
import CID "mo:cid";
import TID "mo:tid";
import DagCbor "mo:dag-cbor";
import AtUri "../../../../AtUri";
import Json "mo:json";

module {

  /// Validation status of the created record
  public type ValidationStatus = {
    /// Record passed Lexicon schema validation
    #valid;

    /// Record validation status unknown (for unrecognized schemas)
    #unknown;
  };

  /// Metadata about a repository commit
  public type CommitMeta = {
    /// Content Identifier representing the commit
    cid : CID.CID;

    /// Timestamp Identifier representing the revision/version
    rev : TID.TID;
  };
};
