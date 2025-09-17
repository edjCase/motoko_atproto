import ServerInfo "../Types/ServerInfo";
import Runtime "mo:core@1/Runtime";

module {
  public type StableData = {
    info : ?ServerInfo.ServerInfo;
  };

  public class Handler(stableData : StableData) {
    var info = stableData.info;

    public func isInitialized() : Bool = info != null;

    public func get() : ServerInfo.ServerInfo {
      let ?i = info else Runtime.trap("Server not initialized");
      return i;
    };

    public func set(newInfo : ServerInfo.ServerInfo) {
      info := ?newInfo;
    };

    public func toStableData() : StableData {
      return {
        info = info;
      };
    };
  };
};
