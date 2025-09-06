import Text "mo:base/Text";
import Array "mo:core@1/Array";
import Json "mo:json@1";
import BaseX "mo:base-x-encoder@2";
import DagCbor "mo:dag-cbor@2";
import CID "mo:cid@1";

module {

  public func toDagCbor(value : Json.Json) : DagCbor.Value {
    // Convert JSON value to DagCbor
    switch (value) {
      case (#null_) #null_;
      case (#bool(b)) #bool(b);
      case (#number(#int(n))) #int(n);
      case (#number(#float(f))) #float(f);
      case (#string(s)) #text(s);
      case (#array(arr)) #array(arr |> Array.map(_, toDagCbor));
      case (#object_(obj)) #map(
        obj |> Array.map<(Text, Json.Json), (Text, DagCbor.Value)>(
          _,
          func(pair : (Text, Json.Json)) : (Text, DagCbor.Value) {
            let key = pair.0;
            let value = toDagCbor(pair.1);
            (key, value);
          },
        )
      );
    };
  };

  public func fromDagCbor(value : DagCbor.Value) : Json.Json {
    // Convert DagCbor value to JSON
    switch (value) {
      case (#null_) #null_;
      case (#bool(b)) #bool(b);
      case (#int(i)) #number(#int(i));
      case (#float(f)) #number(#float(f));
      case (#text(t)) #string(t);
      case (#bytes(b)) #string(BaseX.toBase64(b.vals(), #url({ includePadding = false })));
      case (#array(arr)) #array(arr |> Array.map(_, fromDagCbor));
      case (#map(m)) #object_(
        m |> Array.map<(Text, DagCbor.Value), (Text, Json.Json)>(
          _,
          func(pair : (Text, DagCbor.Value)) : (Text, Json.Json) {
            let key = pair.0;
            let value = fromDagCbor(pair.1);
            (key, value);
          },
        )
      );
      case (#cid(cid)) #string(CID.toText(cid));
    };
  };

};
