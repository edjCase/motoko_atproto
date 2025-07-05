import DagCbor "mo:dag-cbor";
import Result "mo:base/Result";
import Repository "./Types/Repository";

module {
    public func validateRecord(
        _record : DagCbor.Value,
        _collection : Text,
        _onlyKnownLexicons : Bool,
    ) : Result.Result<Repository.ValidationStatus, Text> {
        // Perform Lexicon validation logic here
        // TODO
        #ok(#unknown);
    };
};
