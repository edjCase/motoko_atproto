import Text "mo:base/Text";
import Array "mo:new-base/Array";
import Repository "./Types/Repository";
import RepositoryHandler "Handlers/RepositoryHandler";
import ServerInfoHandler "Handlers/ServerInfoHandler";
import RouteContext "mo:liminal/RouteContext";
import Route "mo:liminal/Route";
import Serde "mo:serde";
import DID "mo:did";
import Domain "mo:url-kit/Domain";
import CID "mo:cid";
import TID "mo:tid";

module {

    public class Router(
        repositoryHandler : RepositoryHandler.Handler,
        serverInfoHandler : ServerInfoHandler.Handler,
    ) {

        public func routeGet<system>(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
            // TODO query vs update
            route(routeContext);
        };

        public func routePost<system>(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
            route(routeContext);
        };

        func route(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
            let nsid = routeContext.getRouteParam("nsid");
            let _data = routeContext.httpContext.request.body;

            switch (Text.toLowercase(nsid)) {
                case ("_health") health(routeContext);
                case ("com.atproto.server.describeserver") describeServer(routeContext);
                case ("com.atproto.repo.describerepo") describeRepo(routeContext);
                case ("com.atproto.server.listrepos") listRepos(routeContext);
                case (_) {
                    routeContext.buildResponse(
                        #badRequest,
                        #error(#message("Unsupported NSID: " # nsid)),
                    );
                };
            };

        };

        func health(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
            routeContext.buildResponse(
                #ok,
                #content(#Record([("version", #Text("0.0.1")), /* TODO: use actual version */])),
            );
        };

        func describeServer(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
            let ?info = serverInfoHandler.get() else return routeContext.buildResponse(
                #badRequest,
                #error(#message("Server not initialized")),
            );

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

            routeContext.buildResponse(
                #ok,
                #content(#Record([("did", #Text(DID.Plc.toText(info.plcDid))), ("availableUserDomains", #Array([#Text("." # Domain.toText(info.domain))])), ("inviteCodeRequired", #Bool(true)), ("links", #Record(linksCandid)), ("contact", #Record(contactCandid))])),
            );
        };

        func describeRepo(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
            let ?repoId = routeContext.getQueryParam("repo") else return routeContext.buildResponse(
                #badRequest,
                #error(#message("Missing 'repo' query parameter")),
            );
            let repoDid = switch (DID.Plc.fromText(repoId)) {
                case (#err(e)) return routeContext.buildResponse(
                    #badRequest,
                    #error(#message("Invalid repo DID '" # repoId # "': " # e)),
                );
                case (#ok(did)) did;
            };
            let ?repo = repositoryHandler.get(repoDid) else return routeContext.buildResponse(
                #notFound,
                #error(#message("Repository not found")),
            );

            var fields : [(Text, Serde.Candid)] = [
                ("did", #Text(DID.Plc.toText(repo.did))),
                ("head", #Text(CID.toText(repo.head))),
                ("rev", #Nat64(TID.toNat64(repo.rev))),
                ("active", #Bool(repo.active)),
            ];

            switch (repo.status) {
                case (null) ();
                case (?status) {
                    fields := Array.concat(fields, [("status", #Text(status))]);
                };
            };

            routeContext.buildResponse(#ok, #content(#Record(fields)));
        };

        func listRepos(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
            // TODO pagination/cursor
            let repos = repositoryHandler.getAll();
            let reposCandid = Array.map<Repository.Repository, Serde.Candid>(
                repos,
                func(repo : Repository.Repository) : Serde.Candid {

                    var fields : [(Text, Serde.Candid)] = [
                        ("did", #Text(DID.Plc.toText(repo.did))),
                        ("head", #Text(CID.toText(repo.head))),
                        ("rev", #Nat64(TID.toNat64(repo.rev))),
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

            routeContext.buildResponse(
                #ok,
                #content(
                    #Record([
                        ("repos", #Array(reposCandid)),
                    ])
                ),
            );
        };
    };

};
