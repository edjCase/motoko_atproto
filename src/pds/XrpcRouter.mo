import Text "mo:base/Text";
import Array "mo:new-base/Array";
import Repository "./Types/Repository";
import RepositoryHandler "Handlers/RepositoryHandler";
import ServerInfoHandler "Handlers/ServerInfoHandler";
import AccountHandler "Handlers/AccountHandler";
import RouteContext "mo:liminal/RouteContext";
import Route "mo:liminal/Route";
import Serde "mo:serde";
import DID "mo:did";
import Domain "mo:url-kit/Domain";
import CID "mo:cid";
import TID "mo:tid";
import Json "mo:json";
import Result "mo:base/Result";
import Nat "mo:new-base/Nat";
import DescribeRepo "./Types/Lexicons/Com/Atproto/Repo/DescribeRepo";
import CreateRecord "./Types/Lexicons/Com/Atproto/Repo/CreateRecord";
import GetRecord "./Types/Lexicons/Com/Atproto/Repo/GetRecord";
import PutRecord "./Types/Lexicons/Com/Atproto/Repo/PutRecord";
import DeleteRecord "./Types/Lexicons/Com/Atproto/Repo/DeleteRecord";
import ListRecords "./Types/Lexicons/Com/Atproto/Repo/ListRecords";
import UploadBlob "./Types/Lexicons/Com/Atproto/Repo/UploadBlob";
import RepoCommon "./Types/Lexicons/Com/Atproto/Repo/Common";
import ListBlobs "./Types/Lexicons/Com/Atproto/Sync/ListBlobs";
import CreateSession "./Types/Lexicons/Com/Atproto/Server/CreateSession";
import CreateAccount "./Types/Lexicons/Com/Atproto/Server/CreateAccount";

module {

    public class Router(
        repositoryHandler : RepositoryHandler.Handler,
        serverInfoHandler : ServerInfoHandler.Handler,
        accountHandler : AccountHandler.Handler,
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
                case ("com.atproto.repo.applywrites") await* applyWrites(routeContext);
                case ("com.atproto.repo.createrecord") await* createRecord(routeContext);
                case ("com.atproto.repo.deleterecord") await* deleteRecord(routeContext);
                case ("com.atproto.repo.describerepo") await* describeRepo(routeContext);
                case ("com.atproto.repo.getrecord") getRecord(routeContext);
                case ("com.atproto.repo.importRepo") importRepo(routeContext);
                case ("com.atproto.repo.listmissingblobs") listMissingBlobs(routeContext);
                case ("com.atproto.repo.listrecords") listRecords(routeContext);
                case ("com.atproto.repo.putrecord") await* putRecord(routeContext);
                case ("com.atproto.repo.uploadblob") uploadBlob(routeContext);
                case ("com.atproto.server.createaccount") await* createAccount(routeContext);
                case ("com.atproto.server.createsession") await* createSession(routeContext);
                case ("com.atproto.server.getsession") getSession(routeContext);
                case ("com.atproto.server.describeserver") describeServer(routeContext);
                case ("com.atproto.sync.listblobs") listBlobs(routeContext);
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

        func applyWrites(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {
            // TODO: Implement applyWrites
            routeContext.buildResponse(
                #internalServerError,
                #error(#message("applyWrites not implemented yet")),
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

            let request : DescribeRepo.Request = {
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
            let responseJson = DescribeRepo.toJson(response);
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

            let request = switch (parseRequestFromBody(routeContext, CreateRecord.fromJson)) {
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
            let responseJson = CreateRecord.toJson(response);
            routeContext.buildResponse(
                #ok,
                #json(responseJson),
            );
        };

        func putRecord(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {
            let request = switch (parseRequestFromBody(routeContext, PutRecord.fromJson)) {
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
            let responseJson = PutRecord.toJson(response);
            routeContext.buildResponse(
                #ok,
                #json(responseJson),
            );
        };

        func deleteRecord(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {
            let request = switch (parseRequestFromBody(routeContext, DeleteRecord.fromJson)) {
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
            let responseJson = DeleteRecord.toJson(response);
            routeContext.buildResponse(
                #ok,
                #json(responseJson),
            );
        };

        func getRecord(routeContext : RouteContext.RouteContext) : Route.HttpResponse {

            let request = switch (parseRequestFromBody(routeContext, GetRecord.fromJson)) {
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

            let responseJson = GetRecord.toJson(response);
            routeContext.buildResponse(
                #ok,
                #json(responseJson),
            );
        };

        func importRepo(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
            // TODO: Implement repo import
            routeContext.buildResponse(
                #notImplemented,
                #error(#message("importRepo not implemented yet")),
            );
        };

        func listRecords(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
            // TODO: Implement record listing with MST traversal
            routeContext.buildResponse(
                #notImplemented,
                #error(#message("listRecords not implemented yet")),
            );
        };

        func uploadBlob(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
            let mimeType = switch (routeContext.getHeader("Content-Type")) {
                case (null) "application/octet-stream"; // Default to binary
                case (?mimeType) mimeType;
            };

            let data = routeContext.httpContext.request.body;

            if (data.size() == 0) {
                return routeContext.buildResponse(
                    #badRequest,
                    #error(#message("Empty request body")),
                );
            };

            let request = {
                data = data;
                mimeType = mimeType;
            };

            let response = switch (repositoryHandler.uploadBlob(request)) {
                case (#ok(response)) response;
                case (#err(e)) {
                    return routeContext.buildResponse(
                        #badRequest,
                        #error(#message("Failed to upload blob: " # e)),
                    );
                };
            };

            let responseJson = UploadBlob.toJson(response);
            routeContext.buildResponse(
                #ok,
                #json(responseJson),
            );
        };

        func listMissingBlobs(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
            // TODO : Implement listMissingBlobs
            routeContext.buildResponse(
                #notImplemented,
                #error(#message("listMissingBlobs not implemented yet")),
            );
        };

        func listBlobs(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
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

            let limitText = routeContext.getQueryParam("limit");
            let limitOrNull = switch (getNatOrnull(limitText)) {
                case (#ok(limit)) limit;
                case (#err) return routeContext.buildResponse(
                    #badRequest,
                    #error(#message("Invalid 'limit' parameter, must be a valid positive integer")),
                );
            };

            let sinceText = routeContext.getQueryParam("since");
            let sinceOrNull = switch (sinceText) {
                case (null) null; // No 'since' parameter means all blobs
                case (?sinceText) switch (TID.fromText(sinceText)) {
                    case (#ok(tid)) ?tid;
                    case (#err(e)) return routeContext.buildResponse(
                        #badRequest,
                        #error(#message("Invalid 'since' parameter, must be a valid TID: " # e)),
                    );
                };
            };

            let cursorText = routeContext.getQueryParam("cursor");

            let request : ListBlobs.Request = {
                did = repo;
                since = sinceOrNull;
                limit = limitOrNull;
                cursor = cursorText;
            };

            let response = switch (repositoryHandler.listBlobs(request)) {
                case (#ok(response)) response;
                case (#err(e)) {
                    return routeContext.buildResponse(
                        #badRequest,
                        #error(#message("Failed to list blobs: " # e)),
                    );
                };
            };

            let responseJson = ListBlobs.toJson(response);
            routeContext.buildResponse(
                #ok,
                #json(responseJson),
            );
        };

        func createAccount(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {
            let request = switch (parseRequestFromBody(routeContext, CreateAccount.fromJson)) {
                case (#ok(req)) req;
                case (#err(e)) return routeContext.buildResponse(
                    #badRequest,
                    #error(#message(e)),
                );
            };

            let response = switch (await* accountHandler.create(request)) {
                case (#ok(response)) response;
                case (#err(e)) return routeContext.buildResponse(
                    #badRequest,
                    #error(#message("Failed to create account: " # e)),
                );
            };
            let responseJson = CreateAccount.toJson(response);
            routeContext.buildResponse(
                #ok,
                #json(responseJson),
            );
        };

        func createSession(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {
            let request = switch (parseRequestFromBody(routeContext, CreateSession.fromJson)) {
                case (#ok(req)) req;
                case (#err(e)) return routeContext.buildResponse(
                    #badRequest,
                    #error(#message(e)),
                );
            };

            let response = switch (await* accountHandler.createSession(request)) {
                case (#ok(response)) response;
                case (#err(e)) return routeContext.buildResponse(
                    #badRequest,
                    #error(#message("Failed to create session: " # e)),
                );
            };
            let responseJson = CreateSession.toJson(response);
            routeContext.buildResponse(
                #ok,
                #json(responseJson),
            );
        };

        func getSession(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
            // TODO: Implement getSession
            routeContext.buildResponse(
                #notImplemented,
                #error(#message("getSession not implemented yet")),
            );
        };

        // Helper functions

        func getNatOrnull(optText : ?Text) : Result.Result<?Nat, ()> {
            switch (optText) {
                case (null) #ok(null);
                case (?text) {
                    switch (Nat.fromText(text)) {
                        case (?n) #ok(?n);
                        case (null) return #err; // Invalid Nat
                    };
                };
            };
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
