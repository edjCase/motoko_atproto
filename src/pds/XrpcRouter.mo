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
import Json "mo:json";
import Result "mo:base/Result";
import DagCbor "mo:dag-cbor";
import Blob "mo:new-base/Blob";
import AtUri "Types/AtUri";
import JsonSerializer "./JsonSerializer";
import Nat "mo:new-base/Nat";

module {

    public class Router(
        repositoryHandler : RepositoryHandler.Handler,
        serverInfoHandler : ServerInfoHandler.Handler,
    ) {

        public func routeGet<system>(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {
            await* routeAsync(routeContext);
        };

        public func routePost<system>(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {
            await* routeAsync(routeContext);
        };

        func routeAsync(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {
            let nsid = routeContext.getRouteParam("nsid");

            switch (Text.toLowercase(nsid)) {
                case ("_health") health(routeContext);
                case ("com.atproto.repo.getrecord") getRecord(routeContext);
                case ("com.atproto.repo.listrecords") listRecords(routeContext);
                case ("com.atproto.repo.createrecord") await* createRecord(routeContext);
                case ("com.atproto.repo.putrecord") await* putRecord(routeContext);
                case ("com.atproto.repo.deleterecord") await* deleteRecord(routeContext);
                case ("com.atproto.repo.describerepo") await* describeRepo(routeContext);
                case ("com.atproto.server.describeserver") describeServer(routeContext);
                case ("com.atproto.sync.listrepos") listRepos(routeContext);
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
                #content(#Record([("version", #Text("0.0.1"))])),
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

        func describeRepo(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {

            let ?repoText = routeContext.getQueryParam("repo") else return routeContext.buildResponse(
                #badRequest,
                #error(#message("Missing required query parameter: repo")),
            );
            let repo = switch (DID.Plc.fromText(repoText)) {
                case (#ok(did)) did;
                case (#err(e)) return routeContext.buildResponse(
                    #badRequest,
                    #error(#message("Invalid repo DID: " # e)),
                );
            };

            let request : Repository.DescribeRepoRequest = {
                repo = repo;
            };
            let response = switch (await* repositoryHandler.describe(request)) {
                case (#ok(response)) response;
                case (#err(e)) {
                    return routeContext.buildResponse(
                        #badRequest,
                        #error(#message("Failed to describe repository: " # e)),
                    );
                };
            };
            let responseJson = JsonSerializer.fromDescribeRepoResponse(response);
            routeContext.buildResponse(
                #ok,
                #json(responseJson),
            );
        };

        func listRepos(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
            let limit = switch (routeContext.getQueryParam("limit")) {
                case (null) 100; // Default limit
                case (?limitText) {
                    switch (Nat.fromText(limitText)) {
                        case (?limit) limit;
                        case (null) return routeContext.buildResponse(
                            #badRequest,
                            #error(#message("Invalid limit parameter: " # limitText)),
                        );
                    };
                };
            };
            // TODO: pagination/cursor
            let repos = repositoryHandler.getAll(limit);
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

        func createRecord(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {

            let request = switch (parseRequestFromBody(routeContext, JsonSerializer.toCreateRecordRequest)) {
                case (#ok(req)) req;
                case (#err(e)) return routeContext.buildResponse(
                    #badRequest,
                    #error(#message(e)),
                );
            };
            let response = switch (await* repositoryHandler.createRecord(request)) {
                case (#ok(response)) response;
                case (#err(e)) {
                    return routeContext.buildResponse(
                        #badRequest,
                        #error(#message("Failed to create record: " # e)),
                    );
                };
            };
            let responseJson = JsonSerializer.fromCreateRecordResponse(response);
            routeContext.buildResponse(
                #ok,
                #json(responseJson),
            );
        };

        func putRecord(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {
            let request = switch (parseRequestFromBody(routeContext, JsonSerializer.toPutRecordRequest)) {
                case (#ok(req)) req;
                case (#err(e)) return routeContext.buildResponse(
                    #badRequest,
                    #error(#message(e)),
                );
            };
            let response = switch (await* repositoryHandler.putRecord(request)) {
                case (#ok(response)) response;
                case (#err(e)) {
                    return routeContext.buildResponse(
                        #notFound,
                        #error(#message("Failed to put record: " # e)),
                    );
                };
            };
            let responseJson = JsonSerializer.fromPutRecordResponse(response);
            routeContext.buildResponse(
                #ok,
                #json(responseJson),
            );
        };

        func deleteRecord(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {
            let request = switch (parseRequestFromBody(routeContext, JsonSerializer.toDeleteRecordRequest)) {
                case (#ok(req)) req;
                case (#err(e)) return routeContext.buildResponse(
                    #badRequest,
                    #error(#message(e)),
                );
            };
            let response = switch (await* repositoryHandler.deleteRecord(request)) {
                case (#ok(response)) response;
                case (#err(e)) {
                    return routeContext.buildResponse(
                        #notFound,
                        #error(#message("Failed to delete record: " # e)),
                    );
                };
            };
            let responseJson = JsonSerializer.fromDeleteRecordResponse(response);
            routeContext.buildResponse(
                #ok,
                #json(responseJson),
            );
        };

        func getRecord(routeContext : RouteContext.RouteContext) : Route.HttpResponse {

            let request = switch (parseRequestFromBody(routeContext, JsonSerializer.toGetRecordRequest)) {
                case (#ok(req)) req;
                case (#err(e)) return routeContext.buildResponse(
                    #badRequest,
                    #error(#message(e)),
                );
            };

            let response = switch (repositoryHandler.getRecord(request)) {
                case (#ok(response)) response;
                case (#err(e)) {
                    return routeContext.buildResponse(
                        #notFound,
                        #error(#message("Failed to get record: " # e)),
                    );
                };
            };

            let responseJson = JsonSerializer.fromGetRecordResponse(response);
            routeContext.buildResponse(
                #ok,
                #json(responseJson),
            );
        };

        func listRecords(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
            // TODO: Implement record listing with MST traversal
            routeContext.buildResponse(
                #notImplemented,
                #error(#message("listRecords not implemented yet")),
            );
        };

        func parseRequestFromBody<T>(
            routeContext : RouteContext.RouteContext,
            parser : Json.Json -> Result.Result<T, Text>,
        ) : Result.Result<T, Text> {
            let requestBody = routeContext.httpContext.request.body;
            let ?jsonText = Text.decodeUtf8(requestBody) else return #err("Invalid UTF-8 in request body");

            let parsedJson = switch (Json.parse(jsonText)) {
                case (#ok(json)) json;
                case (#err(e)) return #err("Invalid request JSON: " # debug_show (e));
            };

            // Extract fields from JSON
            switch (parser(parsedJson)) {
                case (#ok(req)) #ok(req);
                case (#err(e)) return #err("Invalid request: " # e);
            };
        };
    };
};
