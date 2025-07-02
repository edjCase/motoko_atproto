import Text "mo:base/Text";
import Result "mo:base/Result";
import Array "mo:new-base/Array";
import Repository "./Types/Repository";
import RepositoryHandler "Handlers/RepositoryHandler";
import ServerInfoHandler "Handlers/ServerInfoHandler";
import RouteContext "mo:liminal/RouteContext";
import Route "mo:liminal/Route";
import Serde "mo:serde";

module {

    public class Router(
        repositoryHandler : RepositoryHandler.Handler,
        serverInfoHandler : ServerInfoHandler.Handler,
    ) {

        public func routeGet(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
            // TODO query vs update
            route(routeContext);
        };

        public func routePost<system>(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
            route(routeContext);
        };

        func route(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
            let nsid = routeContext.getRouteParam("nsid");
            let _data = routeContext.httpContext.request.body;

            let result : Result.Result<Any, Text> = switch (nsid) {
                case ("_health") health();
                case ("com.atproto.server.describeServer") describeServer();
                case ("com.atproto.server.listRepos") listRepos();
                case (_) return routeContext.buildResponse(#internalServerError, #error(#message("Not implemented NSID: " # nsid)));
            };

            switch (result) {
                case (#ok(candidResponse)) routeContext.buildResponse(#ok, #content(candidResponse));
                case (#err(err)) routeContext.buildResponse(#internalServerError, #error(#message(err))); // TODO status code?
            }

        };

        func health() : Result.Result<Serde.Candid, Text> = #ok(
            #Record([
                ("version", #Text("0.0.1")), // TODO: use actual version
            ])
        );

        func describeServer() : Result.Result<Serde.Candid, Text> {
            let ?info = serverInfoHandler.get() else return #err("Server not initialized");

            let linksCandid = [
                // ("privacyPolicy", #Text(info.privacyPolicy)), // TODO?
                // ("termsOfService", #Text(info.termsOfService)), // TODO?
            ];

            let contactCandid = switch (info.contactEmailAddress) {
                case (null) [];
                case (?email) [
                    ("email", #Text(email)),
                ];
            };

            #ok(
                #Record([
                    ("did", #Text(info.did)),
                    ("availableUserDomains", #Array(["." # info.domain])),
                    ("inviteCodeRequired", #Bool(true)),
                    ("links", #Record(linksCandid)),
                    ("contact", #Record(contactCandid)),
                ])
            );
        };

        func listRepos() : Result.Result<Serde.Candid, Text> {
            // TODO pagination/cursor
            let repos = repositoryHandler.getAll();
            let reposCandid = Array.map<Repository.Repository, Serde.Candid>(
                repos,
                func(repo : Repository.Repository) : Serde.Candid {

                    var fields = [
                        ("did", #Text(repo.did)),
                        ("head", #Text(repo.head)),
                        ("rev", #Nat64(repo.rev)),
                        ("active", #Bool(repo.active)),
                    ];

                    switch (repo.status) {
                        case (null) ();
                        case (?status) {
                            fields := Array.concat(fields, [("status", #Text(status))]);
                        };
                    };

                    #Record(fields);
                },
            );

            #ok(
                #Record([
                    ("repos", #Array(reposCandid)),
                ])
            );
        };
    };

};
