import Json "mo:json@1";
import Result "mo:core@1/Result";

module {
  // com.atproto.sync.requestCrawl
  // Request a service to persistently crawl hosted repos. Expected use is new PDS instances declaring their existence to Relays. Does not require auth.

  public type Request = {
    hostname : Text;
  };

  public type Error = {
    #hostBanned;
  };

  public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
    switch (json) {
      case (#object_(fields)) {
        var hostname : ?Text = null;

        for ((key, value) in fields.vals()) {
          switch (key) {
            case ("hostname") {
              switch (value) {
                case (#string(s)) { hostname := ?s };
                case (_) { return null };
              };
            };
            case (_) {};
          };
        };

        switch (hostname) {
          case (?h) { ?{ hostname = h } };
          case (_) { null };
        };
      };
      case (_) { null };
    };
  };

};
