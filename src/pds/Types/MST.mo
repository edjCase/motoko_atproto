import Blob "mo:new-base/Blob";
import CID "mo:cid";
import Nat "mo:new-base/Nat";
import Text "mo:new-base/Text";

module {
    public type Node = {
        l : ?CID.CID;
        e : [TreeEntry];
    };

    public type TreeEntry = {
        p : Nat;
        k : [Nat8];
        v : CID.CID;
        t : ?CID.CID;
    };

    public type KeyValue = {
        key : [Nat8]; // Full key as byte array
        value : CID.CID; // CID pointing to record
    };

    // Create an empty MST (single empty node)
    public func empty() : Node {
        {
            l = null;
            e = [];
        };
    };

    // Convert text path to byte array
    public func pathToKey(path : Text) : [Nat8] {
        Text.encodeUtf8(path) |> Blob.toArray(_);
    };

};
