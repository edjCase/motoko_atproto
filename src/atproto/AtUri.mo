import Text "mo:core@1/Text";
import TextX "mo:xtended-text@2/TextX";
import DID "mo:did@3";

module {

  public type AtUri = {
    authority : { #handle : Text; #plc : DID.Plc.DID };
    collection : ?{
      id : Text;
      recordKey : ?Text;
    };
  };

  public func toText(uri : AtUri) : Text {
    let authority = switch (uri.authority) {
      case (#handle(handle)) handle;
      case (#plc(plcDid)) DID.Plc.toText(plcDid);
    };
    let uriText = "at://" # authority;
    let suffix = switch (uri.collection) {
      case (null) return uriText;
      case (?{ id; recordKey = null }) "/" # id;
      case (?{ id; recordKey = ?recordKey }) "/" # id # "/" # recordKey;
    };
    uriText # suffix;
  };

  public func fromText(path : Text) : ?AtUri {
    let parts = Text.split(path, #char('/'));

    let ?atScheme = parts.next() else return null;
    if (atScheme != "at:") return null; // Ensure it starts with "at:"
    let ?_ = parts.next() else return null;
    let ?authorityText = parts.next() else return null;
    if (TextX.isEmptyOrWhitespace(authorityText)) return null; // Ensure repoId is not empty
    let ?collectionId = parts.next() else return null;
    if (TextX.isEmptyOrWhitespace(collectionId)) return null; // Ensure collectionId is not empty
    let ?recordKey = parts.next() else return null;
    if (TextX.isEmptyOrWhitespace(recordKey)) return null; // Ensure recordKey is not empty
    let null = parts.next() else return null; // Ensure no extra parts

    let authority = switch (DID.Plc.fromText(authorityText)) {
      case (#ok(plc)) #plc(plc);
      case (#err(_)) #handle(authorityText); // TODO validate handle format?
    };
    ?{
      authority = authority;
      collection = ?{
        id = collectionId;
        recordKey = ?recordKey;
      };
    };
  };
};
