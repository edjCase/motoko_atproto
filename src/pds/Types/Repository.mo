import DID "mo:did";
import CID "mo:cid";
import TID "mo:tid";

module {

    public type Repository = {
        did : DID.Plc.DID; // DID of the repository
        head : CID.CID; // CID of current commit
        rev : TID.TID; // TID timestamp
        active : Bool;
        status : ?Text; // Optional status if not active
    };
};
