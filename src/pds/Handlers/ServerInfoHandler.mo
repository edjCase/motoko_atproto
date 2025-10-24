import ServerInfo "../ServerInfo";
import Runtime "mo:core@1/Runtime";

module {
  public type StableData = ServerInfo.ServerInfo;

  public class Handler(stableData : ?StableData) {
    var serverInfoOrNull = stableData;

    public func get() : ServerInfo.ServerInfo {
      let ?serverInfo = serverInfoOrNull else Runtime.trap("ServerInfo not set");
      serverInfo;
    };

    public func set(newInfo : ServerInfo.ServerInfo) : () {
      serverInfoOrNull := ?newInfo;
    };

    public func toStableData() : ?StableData = serverInfoOrNull;
  };
};
