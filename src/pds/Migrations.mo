module {
  public func hostname(
    state : {
      var serverInfoStableData : {
        info : ?{
          domain : {
            name : Text;
            suffix : Text;
            subdomains : [Text];
          };
          plcDid : {
            identifier : Text;
          };
          contactEmailAddress : ?Text;
        };
      };
    }
  ) : {
    var serverInfoStableData : {
      info : ?{
        hostname : Text;
        plcDid : {
          identifier : Text;
        };
        contactEmailAddress : ?Text;
      };
    };
  } {
    let info = switch (state.serverInfoStableData.info) {
      case (null) null;
      case (?info) (
        ?{
          info with
          hostname = info.domain.name # "." # info.domain.suffix;
        }
      );
    };
    {
      var serverInfoStableData = {
        info = info;
      };
    };
  };
};
