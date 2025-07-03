import DID "mo:did";
import CID "mo:cid";
import TID "mo:tid";
import Commit "./Commit";

module {

    public type RepositoryWithoutDID = {
        head : CID.CID; // CID of current commit
        rev : TID.TID; // TID timestamp
        active : Bool;
        status : ?Text; // Optional status if not active
    };

    public type Repository = RepositoryWithoutDID and {
        did : DID.Plc.DID; // DID of the repository
    };
};
