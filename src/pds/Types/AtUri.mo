import Text "mo:new-base/Text";
import TextX "mo:xtended-text/TextX";
import CID "mo:cid";
module {

    public type AtUri = {
        repoId : DID.Plc.DID;
        collectionAndRecord : ?(Text, ?Text);
    };

    public func toText(uri : AtUri) : Text {
        let uri = "at://" # DID.Plc.toText(uri.repoId);
        let suffix = switch (uri.collectionAndRecord) {
            case (null) return uri;
            case (?collection, null) "/" # collection;
            case (?collection, ?record) "/" #collection # "/" #record;
        };
        uri # suffix;
    };

    public func fromText(path : Text) : ?AtUri {
        let parts = Text.split(path, #char('/'));

        let ?atScheme = parts.next() else return null;
        if (atScheme != "at:") return null; // Ensure it starts with "at:"
        let ?_ = parts.next() else return null;
        let ?repoId = parts.next() else return null;
        if (TextX.isEmptyOrWhitespace(repoId)) return null; // Ensure repoId is not empty
        let ?collectionId = parts.next() else return null;
        if (TextX.isEmptyOrWhitespace(collectionId)) return null; // Ensure collectionId is not empty
        let ?recordKey = parts.next() else return null;
        if (TextX.isEmptyOrWhitespace(recordKey)) return null; // Ensure recordKey is not empty
        let null = parts.next() else return null; // Ensure no extra parts

        ?{
            repoId = CID.fromText(repoId);
            collectionId = collectionId;
            recordKey = recordKey;
        };
    };
};
