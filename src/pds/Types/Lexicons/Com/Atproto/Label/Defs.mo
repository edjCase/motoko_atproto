import Json "mo:json";
import AtUri "../../../../AtUri";
import DID "mo:did";
import CID "mo:cid";
import Option "mo:core/Option";
import DateTime "mo:datetime/DateTime";
import BaseX "mo:base-x-encoder";

module {

  /// A label object
  public type Label = {
    /// Source of the label
    src : DID.DID; // DID string

    /// URI of the labeled resource
    uri : AtUri.AtUri; // URI string

    /// CID of the labeled resource
    cid : ?CID.CID; // CID string

    /// Label value
    val : Text;

    /// Negation flag
    neg : ?Bool;

    /// Creation timestamp
    cts : Nat; // Epoch Nanoseconds

    /// Expiration timestamp
    exp : ?Nat; // Epoch Nanoseconds

    /// Signature
    sig : ?Blob;
  };

  public func labelToJson(label_ : Label) : Json.Json {
    #object_([
      ("$type", #string("com.atproto.label.defs#label")),
      ("src", #string(DID.toText(label_.src))),
      ("uri", #string(AtUri.toText(label_.uri))),
      (
        "cid",
        Option.getMapped<CID.CID, Json.Json>(label_.cid, func(x) = #string(CID.toText(x)), #null_),
      ),
      ("val", #string(label_.val)),
      (
        "neg",
        Option.getMapped<Bool, Json.Json>(label_.neg, func(x) = #bool(x), #null_),
      ),
      ("cts", #string(DateTime.DateTime(label_.cts).toText())),
      (
        "exp",
        Option.getMapped<Nat, Json.Json>(label_.exp, func(x) = #string(DateTime.DateTime(x).toText()), #null_),
      ),
      (
        "sig",
        Option.getMapped<Blob, Json.Json>(label_.sig, func(x) = #string(BaseX.toBase64(x.vals(), #standard({ includePadding = true }))), #null_),
      ),
    ]);
  };

};
