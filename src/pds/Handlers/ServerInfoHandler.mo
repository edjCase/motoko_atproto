import ServerInfo "../Types/ServerInfo";

module {
  public type StableData = {
    info : ?ServerInfo.ServerInfo;
  };

  public class Handler(stableData : StableData) {
    var info = stableData.info;

    public func get() : ?ServerInfo.ServerInfo {
      return info;
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
