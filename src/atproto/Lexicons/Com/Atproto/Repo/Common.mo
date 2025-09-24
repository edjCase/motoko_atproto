import DID "mo:did@3";
import CID "mo:cid@1";
import TID "mo:tid@1";
import DagCbor "mo:dag-cbor@2";
import AtUri "../../../../AtUri";
import Json "mo:json@1";

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
