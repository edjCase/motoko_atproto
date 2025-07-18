import DagCbor "mo:dag-cbor";
import Result "mo:base/Result";
import RepoCommon "./Types/Lexicons/Com/Atproto/Repo/Common";

module {
    public func validateRecord(
        _record : DagCbor.Value,
        _collection : Text,
        _onlyKnownLexicons : Bool,
    ) : Result.Result<RepoCommon.ValidationStatus, Text> {
        // Perform Lexicon validation logic here
        // TODO
        #ok(#unknown);
    };
};
