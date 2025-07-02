import Domain "mo:url-kit/Domain";
import PlcDID "mo:did/Plc";

module {
    public type ServerInfo = {
        domain : Domain.Domain;
        plcDid : PlcDID.DID;
        contactEmailAddress : ?Text;
    };
};
