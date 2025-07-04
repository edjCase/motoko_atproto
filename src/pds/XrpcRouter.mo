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

module {

    public class Router(
        repositoryHandler : RepositoryHandler.Handler,
        serverInfoHandler : ServerInfoHandler.Handler,
    ) {

        public func routeGet<system>(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
            route(routeContext);
        };

        public func routePost<system>(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {
            await* routeAsync(routeContext);
        };

        func route(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
            let nsid = routeContext.getRouteParam("nsid");

            switch (Text.toLowercase(nsid)) {
                case ("_health") health(routeContext);
                case ("com.atproto.server.describeserver") describeServer(routeContext);
                case ("com.atproto.repo.describerepo") describeRepo(routeContext);
                case ("com.atproto.server.listrepos") listRepos(routeContext);
                case ("com.atproto.repo.getrecord") getRecord(routeContext);
                case ("com.atproto.repo.listrecords") listRecords(routeContext);
                case (_) {
                    routeContext.buildResponse(
                        #badRequest,
                        #error(#message("Unsupported NSID: " # nsid)),
                    );
                };
            };
        };

        func routeAsync(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {
            let nsid = routeContext.getRouteParam("nsid");

            switch (Text.toLowercase(nsid)) {
                case ("com.atproto.repo.createrecord") await* createRecord(routeContext);
                case ("com.atproto.repo.putrecord") await* putRecord(routeContext);
                case ("com.atproto.repo.deleterecord") await* deleteRecord(routeContext);
                case (_) route(routeContext); // Fall back to sync routes
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
            // TODO: pagination/cursor
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

        func createRecord(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {
            // Parse request body
            let requestBody = routeContext.httpContext.request.body;
            let ?jsonText = Text.decodeUtf8(requestBody) else return routeContext.buildResponse(
                #badRequest,
                #error(#message("Invalid UTF-8 in request body")),
            );

            let parsedJson = switch (Json.parse(jsonText)) {
                case (#ok(json)) json;
                case (#err(e)) return routeContext.buildResponse(
                    #badRequest,
                    #error(#message("Invalid JSON: " # debug_show (e))),
                );
            };

            // Extract fields from JSON
            let createRecordRequest = switch (parseCreateRecordRequest(parsedJson)) {
                case (#ok(req)) req;
                case (#err(e)) return routeContext.buildResponse(
                    #badRequest,
                    #error(#message("Invalid request: " # e)),
                );
            };

            let record = JsonSerializer.toDagCbor(createRecordRequest.record);

            let recordCIDResult = await* repositoryHandler.createRecord(
                createRecordRequest.repo,
                createRecordRequest.collection,
                createRecordRequest.rkey,
                record,
            );

            switch (recordCIDResult) {
                case (#ok({ uri; cid })) {
                    routeContext.buildResponse(
                        #ok,
                        #json(
                            #object_([
                                ("uri", #string(AtUri.toText(atUri))),
                                ("cid", #string(CID.toText(recordCID))),
                            ])
                        ),
                    );
                };
                case (#err(e)) {
                    routeContext.buildResponse(
                        #internalServerError,
                        #error(#message("Failed to create record: " # e)),
                    );
                };
            };
        };

        func putRecord(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {
            // Parse request body
            let requestBody = routeContext.httpContext.request.body;
            let ?jsonText = Text.decodeUtf8(requestBody) else return routeContext.buildResponse(
                #badRequest,
                #error(#message("Invalid UTF-8 in request body")),
            );

            let parsedJson = switch (Json.parse(jsonText)) {
                case (#ok(json)) json;
                case (#err(e)) return routeContext.buildResponse(
                    #badRequest,
                    #error(#message("Invalid JSON: " # debug_show (e))),
                );
            };

            // Extract fields from JSON
            let putRecordRequest = switch (parsePutRecordRequest(parsedJson)) {
                case (#ok(req)) req;
                case (#err(e)) return routeContext.buildResponse(
                    #badRequest,
                    #error(#message("Invalid request: " # e)),
                );
            };

            let record = JsonSerializer.toDagCbor(putRecordRequest.record);

            let recordCIDResult = await* repositoryHandler.putRecord(
                putRecordRequest.repo,
                putRecordRequest.collection,
                putRecordRequest.rkey,
                record,
            );

            switch (recordCIDResult) {
                case (#ok({ uri; cid })) {
                    routeContext.buildResponse(
                        #ok,
                        #json(
                            #object_([
                                ("uri", #string(AtUri.toText(uri))),
                                ("cid", #string(CID.toText(cid))),
                            ])
                        ),
                    );
                };
                case (#err(e)) {
                    routeContext.buildResponse(
                        #internalServerError,
                        #error(#message("Failed to create record: " # e)),
                    );
                };
            };
        };

        func deleteRecord(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {
            // Delete record implementation
            routeContext.buildResponse(
                #notImplemented,
                #error(#message("deleteRecord not implemented yet")),
            );
        };

        func getRecord(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
            let ?repo = routeContext.getQueryParam("repo") else return routeContext.buildResponse(
                #badRequest,
                #error(#message("Missing 'repo' parameter")),
            );
            let repoDid = switch (DID.Plc.fromText(repo)) {
                case (#err(e)) return routeContext.buildResponse(
                    #badRequest,
                    #error(#message("Invalid repo DID '" # repo # "': " # e)),
                );
                case (#ok(did)) did;
            };
            let ?collection = routeContext.getQueryParam("collection") else return routeContext.buildResponse(
                #badRequest,
                #error(#message("Missing 'collection' parameter")),
            );
            let ?rkey = routeContext.getQueryParam("rkey") else return routeContext.buildResponse(
                #badRequest,
                #error(#message("Missing 'rkey' parameter")),
            );

            let ?{ cid; value } = repositoryHandler.getRecord(repoDid, collection, rkey) else return routeContext.buildResponse(
                #notFound,
                #error(#message("Record not found")),
            );
            let atUri = AtUri.toText({
                repoId = repoDid;
                collectionAndRecord = ?(collection, ?rkey);
            });
            let valueJson = JsonSerializer.fromDagCbor(value);
            routeContext.buildResponse(
                #ok,
                #json(
                    #object_([
                        ("uri", #string(atUri)),
                        ("cid", #string(CID.toText(cid))),
                        ("value", valueJson),
                    ])
                ),
            );
        };

        func listRecords(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
            // TODO: Implement record listing with MST traversal
            routeContext.buildResponse(
                #notImplemented,
                #error(#message("listRecords not implemented yet")),
            );
        };

        private func parseCreateRecordRequest(json : Json.Json) : Result.Result<CreateRecordRequest, Text> {
            // Parse JSON into CreateRecordRequest
            // This is a simplified implementation
            #err("JSON parsing not implemented");
        };
    };
};
