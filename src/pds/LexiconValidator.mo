module {
    public func validateRecord(
        record : DagCbor.Value,
        collection : Text,
        onlyKnownLexicons : Bool,
    ) : async Result.Result<ValidationStatus, Text> {
        // Perform Lexicon validation logic here
        // TODO
    };
};
