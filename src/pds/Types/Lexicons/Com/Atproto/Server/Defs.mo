import Json "mo:json";
import Array "mo:base/Array";

module {

  public type InviteCodeUse = {
    usedBy : Text; // DID string
    usedAt : Text; // datetime string
  };

  public type InviteCode = {
    code : Text;
    available : Int;
    disabled : Bool;
    forAccount : Text;
    createdBy : Text;
    createdAt : Text; // datetime string
    uses : [InviteCodeUse];
  };

  public func inviteCodeUseToJson(use : InviteCodeUse) : Json.Json {
    #object_([
      ("usedBy", #string(use.usedBy)),
      ("usedAt", #string(use.usedAt)),
    ]);
  };

  public func inviteCodeToJson(invite : InviteCode) : Json.Json {
    let usesJson = invite.uses |> Array.map<InviteCodeUse, Json.Json>(_, inviteCodeUseToJson);

    #object_([
      ("code", #string(invite.code)),
      ("available", #number(#int(invite.available))),
      ("disabled", #bool(invite.disabled)),
      ("forAccount", #string(invite.forAccount)),
      ("createdBy", #string(invite.createdBy)),
      ("createdAt", #string(invite.createdAt)),
      ("uses", #array(usesJson)),
    ]);
  };

};
