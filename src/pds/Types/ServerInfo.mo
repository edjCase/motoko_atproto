import Domain "mo:url-kit@3/Domain";
import PlcDID "mo:did@3/Plc";
import DID "mo:did@3";
import Text "mo:core@1/Text";
import TextX "mo:xtended-text@2/TextX";

module {
  public type ServerInfo = {
    hostname : Text;
    plcDid : PlcDID.DID;
    contactEmailAddress : ?Text;
  };

  public func buildWebDID(serverInfo : ServerInfo) : DID.Web.DID {
    {
      hostname = serverInfo.hostname;
      path = [];
      port = null;
    };
  };

  public func buildHandleFromAccountName(serverInfo : ServerInfo, name : Text) : Text {
    name # "." # serverInfo.hostname;
  };

  public func getAccountNameFromHandle(serverInfo : ServerInfo, handle : Text) : ?Text {
    let domainText = "." # serverInfo.hostname;
    switch (Text.stripEnd(handle, #text(domainText))) {
      case (null) null;
      case (?name) if (TextX.isEmptyOrWhitespace(name)) null else ?name;
    };
  };
};
