import Json "mo:json@1";
import Result "mo:core@1/Result";
import SyncDefs "./Defs";

module {
  // com.atproto.sync.getHostStatus
  // Returns information about a specified upstream host, as consumed by the server. Implemented by relays.

  public type Params = {
    hostname : Text;
  };

  public type Response = {
    hostname : Text;
    seq : ?Int;
    accountCount : ?Int;
    status : ?SyncDefs.HostStatus;
  };

  public type Error = {
    #hostNotFound;
  };

  public func toJson(response : Response) : Json.Json {

    #object_([
      ("hostname", #string(response.hostname)),
      (
        "seq",
        switch (response.seq) {
          case (?s) { #number(#int(s)) };
          case (null) { #null_ };
        },
      ),
      (
        "accountCount",
        switch (response.accountCount) {
          case (?ac) { #number(#int(ac)) };
          case (null) { #null_ };
        },
      ),
      (
        "status",
        switch (response.status) {
          case (?#active) { #string("active") };
          case (?#idle) { #string("idle") };
          case (?#offline) { #string("offline") };
          case (?#throttled) { #string("throttled") };
          case (?#banned) { #string("banned") };
          case (null) { #null_ };
        },
      ),
    ]);
  };

};
