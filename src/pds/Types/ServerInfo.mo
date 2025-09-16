import Domain "mo:url-kit@3/Domain";
import PlcDID "mo:did@3/Plc";

module {
  public type ServerInfo = {
    hostname : Text;
    plcDid : PlcDID.DID;
    contactEmailAddress : ?Text;
  };
};
