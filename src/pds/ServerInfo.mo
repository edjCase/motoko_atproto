import DID "mo:did@3";
import Text "mo:core@1/Text";
import TextX "mo:xtended-text@2/TextX";

module {
  public type ServerInfo = {
    serviceSubdomain : ?Text;
    hostname : Text;
    plcIdentifier : DID.Plc.DID;
  };

  public func buildWebDID(serverInfo : ServerInfo) : DID.Web.DID {
    {
      hostname = serverInfo.hostname;
      path = [];
      port = null;
    };
  };

  public func buildServerHandle(serverInfo : ServerInfo) : Text = serverInfo.hostname;

  public func isServerHandle(serverInfo : ServerInfo, handle : Text) : Bool {
    TextX.equalIgnoreCase(handle, buildServerHandle(serverInfo));
  };
};
