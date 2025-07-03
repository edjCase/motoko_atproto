import Text "mo:new-base/Text";
module {

    public type AtUri = {
        collectionId : Text;
        recordKey : Text;
    };

    public func toText(uri : AtUri) : Text {
        uri.collectionId # "/" # uri.recordKey;
    };

    public func fromText(path : Text) : ?AtUri {
        let parts = Text.split(path, #char('/'));

        let ?collectionId = parts.next() else return null;
        let ?recordKey = parts.next() else return null;
        let null = parts.next() else return null; // Ensure no extra parts

        ?{
            collectionId = collectionId;
            recordKey = recordKey;
        };
    };
};
