module {

    public type CID = Text; // TODO
    public type TID = Nat64; // Timestamp ID

    public type Repository = {
        did : Text;
        head : CID; // CID of current commit
        rev : TID; // TID timestamp
        active : Bool;
        status : ?Text; // Optional status if not active
    };
};
