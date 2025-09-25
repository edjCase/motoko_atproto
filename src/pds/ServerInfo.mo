import Domain "mo:url-kit@3/Domain";
import DID "mo:did@3";
import Text "mo:core@1/Text";
import TextX "mo:xtended-text@2/TextX";

module {
  public type ServerInfo = {
    hostname : Text;
    plcIdentifier : DID.Plc.DID;
    handlePrefix : ?Text; // TODO should this live here and should i be configurable?
  };

  public func buildWebDID(serverInfo : ServerInfo) : DID.Web.DID {
    {
      hostname = serverInfo.hostname;
      path = [];
      port = null;
    };
  };

  public func buildHandle(serverInfo : ServerInfo) : Text {
    switch (serverInfo.handlePrefix) {
      case (null) serverInfo.hostname;
      case (?handlePrefix) handlePrefix # "." # serverInfo.hostname;
    };
  };

  public func getPrefixFromHandle(serverInfo : ServerInfo, handle : Text) : ?Text {
    let domainText = "." # serverInfo.hostname;
    switch (Text.stripEnd(handle, #text(domainText))) {
      case (null) null;
      case (?name) if (TextX.isEmptyOrWhitespace(name)) null else ?name;
    };
  };
};
