module {

    public type ServerInfo = {
        version : Text;
        did : Text;
        availableUserDomains : [Text];
        inviteCodeRequired : Bool;
        privacyPolicy : Text;
        termsOfService : Text;
        contactEmailAddress : Text;
    };
};
