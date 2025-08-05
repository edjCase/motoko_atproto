import Text "mo:new-base/Text";
import TextX "mo:xtended-text/TextX";
import DID "mo:did";

module {

  public type AtUri = {
    repoId : DID.Plc.DID;
    collectionAndRecord : ?(Text, ?Text);
  };

  public func toText(uri : AtUri) : Text {
    let uriText = "at://" # DID.Plc.toText(uri.repoId);
    let suffix = switch (uri.collectionAndRecord) {
      case (null) return uriText;
      case (?(collection, null)) "/" # collection;
      case (?(collection, ?record)) "/" # collection # "/" # record;
    };
    uriText # suffix;
  };

  public func fromText(path : Text) : ?AtUri {
    let parts = Text.split(path, #char('/'));

    let ?atScheme = parts.next() else return null;
    if (atScheme != "at:") return null; // Ensure it starts with "at:"
    let ?_ = parts.next() else return null;
    let ?repoIdText = parts.next() else return null;
    if (TextX.isEmptyOrWhitespace(repoIdText)) return null; // Ensure repoId is not empty
    let ?collectionId = parts.next() else return null;
    if (TextX.isEmptyOrWhitespace(collectionId)) return null; // Ensure collectionId is not empty
    let ?recordKey = parts.next() else return null;
    if (TextX.isEmptyOrWhitespace(recordKey)) return null; // Ensure recordKey is not empty
    let null = parts.next() else return null; // Ensure no extra parts

    let #ok(repoId) = DID.Plc.fromText(repoIdText) else return null;
    ?{
      repoId = repoId;
      collectionAndRecord = ?(collectionId, ?recordKey);
    };
  };
};
