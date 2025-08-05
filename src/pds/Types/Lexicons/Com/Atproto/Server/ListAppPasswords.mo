import Json "mo:json";
import Array "mo:base/Array";

module {

  public type AppPassword = {
    name : Text;
    createdAt : Text; // datetime string
    privileged : ?Bool;
  };

  public type Response = {
    passwords : [AppPassword];
  };

  public type Error = {
    #accountTakedown : { message : Text };
  };

  public func appPasswordToJson(password : AppPassword) : Json.Json {
    let privilegedJson = switch (password.privileged) {
      case (?p) #bool(p);
      case (null) #null_;
    };

    #object_([
      ("name", #string(password.name)),
      ("createdAt", #string(password.createdAt)),
      ("privileged", privilegedJson),
    ]);
  };

  public func toJson(response : Response) : Json.Json {
    let passwordsJson = response.passwords |> Array.map<AppPassword, Json.Json>(_, appPasswordToJson);

    #object_([
      ("passwords", #array(passwordsJson)),
    ]);
  };

};
