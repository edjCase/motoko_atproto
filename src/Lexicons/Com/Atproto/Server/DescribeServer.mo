import Json "mo:json@1";
import Array "mo:core@1/Array";

module {

  public type Links = {
    privacyPolicy : ?Text;
    termsOfService : ?Text;
  };

  public type Contact = {
    email : ?Text;
  };

  public type Response = {
    inviteCodeRequired : ?Bool;
    phoneVerificationRequired : ?Bool;
    availableUserDomains : [Text];
    links : ?Links;
    contact : ?Contact;
    did : Text; // DID string
  };

  public func linksToJson(links : Links) : Json.Json {
    let privacyPolicyJson = switch (links.privacyPolicy) {
      case (?pp) #string(pp);
      case (null) #null_;
    };

    let termsOfServiceJson = switch (links.termsOfService) {
      case (?tos) #string(tos);
      case (null) #null_;
    };

    #object_([
      ("privacyPolicy", privacyPolicyJson),
      ("termsOfService", termsOfServiceJson),
    ]);
  };

  public func contactToJson(contact : Contact) : Json.Json {
    let emailJson = switch (contact.email) {
      case (?email) #string(email);
      case (null) #null_;
    };

    #object_([
      ("email", emailJson),
    ]);
  };

  public func toJson(response : Response) : Json.Json {
    let inviteCodeRequiredJson = switch (response.inviteCodeRequired) {
      case (?icr) #bool(icr);
      case (null) #null_;
    };

    let phoneVerificationRequiredJson = switch (response.phoneVerificationRequired) {
      case (?pvr) #bool(pvr);
      case (null) #null_;
    };

    let availableUserDomainsJson = #array(response.availableUserDomains |> Array.map<Text, Json.Json>(_, func(domain) = #string(domain)));

    let linksJson = switch (response.links) {
      case (?links) linksToJson(links);
      case (null) #null_;
    };

    let contactJson = switch (response.contact) {
      case (?contact) contactToJson(contact);
      case (null) #null_;
    };

    #object_([
      ("inviteCodeRequired", inviteCodeRequiredJson),
      ("phoneVerificationRequired", phoneVerificationRequiredJson),
      ("availableUserDomains", availableUserDomainsJson),
      ("links", linksJson),
      ("contact", contactJson),
      ("did", #string(response.did)),
    ]);
  };

};
