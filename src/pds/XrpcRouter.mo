import Text "mo:core@1/Text";
import Array "mo:core@1/Array";
import RepositoryHandler "Handlers/RepositoryHandler";
import ServerInfoHandler "Handlers/ServerInfoHandler";
import KeyHandler "Handlers/KeyHandler";
import RouteContext "mo:liminal@1/RouteContext";
import Route "mo:liminal@1/Route";
import Serde "mo:serde";
import DID "mo:did@3";
import CID "mo:cid@1";
import TID "mo:tid@1";
import Json "mo:json@1";
import Result "mo:core@1/Result";
import Nat "mo:core@1/Nat";
import TextX "mo:xtended-text@2/TextX";
import DescribeRepo "../atproto/Lexicons/Com/Atproto/Repo/DescribeRepo";
import CreateRecord "../atproto/Lexicons/Com/Atproto/Repo/CreateRecord";
import GetRecord "../atproto/Lexicons/Com/Atproto/Repo/GetRecord";
import PutRecord "../atproto/Lexicons/Com/Atproto/Repo/PutRecord";
import DeleteRecord "../atproto/Lexicons/Com/Atproto/Repo/DeleteRecord";
import UploadBlob "../atproto/Lexicons/Com/Atproto/Repo/UploadBlob";
import ListBlobs "../atproto/Lexicons/Com/Atproto/Sync/ListBlobs";
import ApplyWrites "../atproto/Lexicons/Com/Atproto/Repo/ApplyWrites";
import GetProfile "../atproto/Lexicons/App/Bsky/Actor/GetProfile";
import GetProfiles "../atproto/Lexicons/App/Bsky/Actor/GetProfiles";
import ActorDefs "../atproto/Lexicons/App/Bsky/Actor/Defs";
import ResolveHandle "../atproto/Lexicons/Com/Atproto/Identity/ResolveHandle";
import ListRecords "../atproto/Lexicons/Com/Atproto/Repo/ListRecords";
import DynamicArray "mo:xtended-collections@0/DynamicArray";
import ServerInfo "ServerInfo";
import DagCbor "mo:dag-cbor@2";
import Debug "mo:core@1/Debug";
import AtUri "../atproto/AtUri";
import DIDModule "./DID";
import CarUtil "./CarUtil";
import CAR "mo:car@1";
import Blob "mo:core@1/Blob";

module {

  public class Router(
    repositoryHandler : RepositoryHandler.Handler,
    serverInfoHandler : ServerInfoHandler.Handler,
    keyHandler : KeyHandler.Handler,
  ) {

    public func routeGet<system>(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {
      await* routeAsync(routeContext);
    };

    public func routePost<system>(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {
      await* routeAsync(routeContext);
    };

    func routeAsync(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {
      let nsid = routeContext.getRouteParam("nsid");

      switch (Text.toLower(nsid)) {
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
        case ("com.atproto.server.describeserver") describeServer(routeContext);
        case ("com.atproto.sync.getrepo") getRepo(routeContext);
        case ("com.atproto.sync.listblobs") listBlobs(routeContext);
        case ("com.atproto.sync.listrepos") listRepos(routeContext);
        case ("com.atproto.identity.resolvehandle") resolveHandle(routeContext);
        case ("app.bsky.actor.getprofile") getProfile(routeContext);
        case ("app.bsky.actor.getprofiles") getProfiles(routeContext);
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
      let request = switch (parseRequestFromBody(routeContext, ApplyWrites.fromJson)) {
        case (#ok(req)) req;
        case (#err(e)) return routeContext.buildResponse(
          #badRequest,
          #error(#message(e)),
        );
      };

      let response = switch (await* repositoryHandler.applyWrites(request)) {
        case (#ok(response)) response;
        case (#err(e)) return routeContext.buildResponse(
          #internalServerError, // TODO how to tell?
          #error(#message("Failed to apply writes: " # e)),
        );
      };
      let serverInfo = serverInfoHandler.get();
      let results = Array.map(
        response.results,
        func(r : RepositoryHandler.WriteResult) : ApplyWrites.WriteResult {
          switch (r) {
            case (#create(c)) #create({
              c with uri = {
                authority = #plc(serverInfo.plcIdentifier);
                collection = ?{
                  id = c.collection;
                  recordKey = ?c.rkey;
                };
              };
            });
            case (#update(u)) #update({
              u with uri = {
                authority = #plc(serverInfo.plcIdentifier);
                collection = ?{
                  id = u.collection;
                  recordKey = ?u.rkey;
                };
              };
            });
            case (#delete(d)) #delete(d);
          };
        },
      );
      let responseJson = ApplyWrites.toJson({ response with results = results });
      routeContext.buildResponse(
        #ok,
        #json(responseJson),
      );
    };

    func describeServer(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
      let serverInfo = serverInfoHandler.get();

      let linksCandid = [
        // ("privacyPolicy", #Text(serverInfo.privacyPolicy)), // TODO?
        // ("termsOfService", #Text(serverInfo.termsOfService)), // TODO?
      ];

      routeContext.buildResponse(
        #ok,
        #content(
          #Record([
            ("did", #Text(DID.Plc.toText(serverInfo.plcIdentifier))),
            ("availableUserDomains", #Array([#Text("." # serverInfo.hostname)])),
            ("inviteCodeRequired", #Bool(true)),
            ("links", #Record(linksCandid)),
            ("contact", #Record([])),
          ])
        ),
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
      let serverInfo = serverInfoHandler.get();
      if (repo != serverInfo.plcIdentifier) {
        return routeContext.buildResponse(
          #notFound,
          #error(#message("Repository not found: " # repoText)),
        );
      };

      let collections = repositoryHandler.getAllCollections();

      let handle = serverInfo.hostname;

      let verificationKey : DID.Key.DID = switch (await* keyHandler.getPublicKey(#verification)) {
        case (#ok(did)) did;
        case (#err(e)) return routeContext.buildResponse(
          #internalServerError,
          #error(#message("Failed to get verification public key: " # e)),
        );
      };
      let alsoKnownAs = [
        AtUri.toText({
          authority = #plc(serverInfo.plcIdentifier);
          collection = null;
        })
      ];
      let didDoc = DIDModule.generateDIDDocument(
        #plc(serverInfo.plcIdentifier),
        alsoKnownAs,
        verificationKey,
      );

      let handleIsCorrect = true; // TODO?

      let response : DescribeRepo.Response = {
        handle = handle;
        did = repo;
        didDoc = didDoc;
        collections = collections;
        handleIsCorrect = handleIsCorrect;
      };
      let responseJson = DescribeRepo.toJson(response);
      routeContext.buildResponse(
        #ok,
        #json(responseJson),
      );
    };

    func listRepos(routeContext : RouteContext.RouteContext) : Route.HttpResponse {

      let serverInfo = serverInfoHandler.get();
      let repository = repositoryHandler.get();
      var fields : [(Text, Serde.Candid)] = [
        ("did", #Text(DID.Plc.toText(serverInfo.plcIdentifier))),
        ("head", #Text(CID.toText(repository.head))),
        ("rev", #Nat64(TID.toNat64(repository.rev))),
        ("active", #Bool(repository.active)),
      ];

      switch (repository.status) {
        case (null) ();
        case (?status) {
          fields := Array.concat(fields, [("status", #Text(status))]);
        };
      };

      routeContext.buildResponse(
        #ok,
        #content(
          #Record([
            ("repos", #Array([#Record(fields)])),
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
      let serverInfo = serverInfoHandler.get();
      let uri : AtUri.AtUri = {
        authority = #plc(serverInfo.plcIdentifier);
        collection = ?{
          id = request.collection;
          recordKey = ?response.rkey;
        };
      };
      let responseJson = CreateRecord.toJson({
        response with uri = uri;
      });
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
      let serverInfo = serverInfoHandler.get();
      let uri : AtUri.AtUri = {
        authority = #plc(serverInfo.plcIdentifier);
        collection = ?{
          id = request.collection;
          recordKey = ?request.rkey;
        };
      };
      let responseJson = PutRecord.toJson({ response with uri = uri });
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

      let request = switch (parseGetRecordRequest(routeContext)) {
        case (#ok(req)) req;
        case (#err(e)) return routeContext.buildResponse(
          #badRequest,
          #error(#message(e)),
        );
      };

      let response = switch (repositoryHandler.getRecord(request)) {
        case (?response) response;
        case (null) return routeContext.buildResponse(
          #notFound,
          #error(#message("Record not found: " # request.collection # "/" # request.rkey)),
        );
      };

      let serverInfo = serverInfoHandler.get();
      let uri : AtUri.AtUri = {
        authority = #plc(serverInfo.plcIdentifier);
        collection = ?{
          id = request.collection;
          recordKey = ?request.rkey;
        };
      };
      let responseJson = GetRecord.toJson({
        response with uri = uri;
        cid = ?response.cid;
      });
      routeContext.buildResponse(
        #ok,
        #json(responseJson),
      );
    };

    func parseGetRecordRequest(routeContext : RouteContext.RouteContext) : Result.Result<GetRecord.Request, Text> {

      // Extract required fields

      let ?repoText = routeContext.getQueryParam("repo") else return #err("Missing required query parameter: repo");

      let repo = switch (DID.Plc.fromText(repoText)) {
        case (#ok(did)) did;
        case (#err(e)) return #err("Invalid repo DID: " # e);
      };

      let ?collection = routeContext.getQueryParam("collection") else return #err("Missing required query parameter: collection");

      let ?rkey = routeContext.getQueryParam("rkey") else return #err("Missing required query parameter: rkey");

      // Extract optional fields
      let cidTextOrNull = routeContext.getQueryParam("cid");

      let cid = switch (cidTextOrNull) {
        case (null) null;
        case (?cidText) switch (CID.fromText(cidText)) {
          case (#ok(cid)) ?cid;
          case (#err(e)) return #err("Invalid cid: " # e);
        };
      };

      #ok({
        repo = repo;
        collection = collection;
        rkey = rkey;
        cid = cid;
      });
    };

    func importRepo(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
      // TODO: Implement repo import
      routeContext.buildResponse(
        #notImplemented,
        #error(#message("importRepo not implemented yet")),
      );
    };

    func listRecords(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
      let repoId = switch (routeContext.getQueryParam("repo")) {
        case (?repoText) switch (DID.Plc.fromText(repoText)) {
          case (#ok(did)) did;
          case (#err(e)) return routeContext.buildResponse(
            #badRequest,
            #error(#message("Invalid repo DID: " # e)),
          );
        };
        case (null) return routeContext.buildResponse(
          #badRequest,
          #error(#message("Missing required query parameter: repo")),
        );
      };
      let collection = switch (routeContext.getQueryParam("collection")) {
        case (?collection) collection;
        case (null) return routeContext.buildResponse(
          #badRequest,
          #error(#message("Missing required query parameter: collection")),
        );
      };
      let limitOrNull = switch (routeContext.getQueryParam("limit")) {
        case (null) null;
        case (?limitText) switch (Nat.fromText(limitText)) {
          case (?n) if (n > 0 and n <= 100) ?n else return routeContext.buildResponse(
            #badRequest,
            #error(#message("Invalid 'limit' parameter, must be between 1 and 100")),
          );
          case (null) return routeContext.buildResponse(
            #badRequest,
            #error(#message("Invalid 'limit' parameter, must be a valid positive integer")),
          );
        };
      };
      let cursorTextOrNull = routeContext.getQueryParam("cursor");
      let reverseOrNull = switch (routeContext.getQueryParam("reverse")) {
        case (null) null;
        case (?reverseText) switch (Text.toLower(reverseText)) {
          case ("true") ?true;
          case ("false") ?false;
          case (_) return routeContext.buildResponse(
            #badRequest,
            #error(#message("Invalid 'reverse' parameter, must be 'true' or 'false'")),
          );
        };
      };

      let serverInfo = serverInfoHandler.get();
      if (repoId != serverInfo.plcIdentifier) {
        return routeContext.buildResponse(
          #notFound,
          #error(#message("Repository not found: " # DID.Plc.toText(repoId))),
        );
      };

      let listRecordsResponse = repositoryHandler.listRecords({
        collection = collection;
        limit = limitOrNull;
        cursor = cursorTextOrNull;
        reverse = reverseOrNull;
        rkeyStart = null;
        rkeyEnd = null;
      });
      let responseJson = ListRecords.toJson({
        listRecordsResponse with records = Array.map(
          listRecordsResponse.records,
          func(r : RepositoryHandler.ListRecord) : ListRecords.ListRecord {
            let uri : AtUri.AtUri = {
              authority = #plc(serverInfo.plcIdentifier);
              collection = ?{
                id = r.collection;
                recordKey = ?r.rkey;
              };
            };
            {
              uri = uri;
              cid = r.cid;
              value = r.value;
            };
          },
        );
      });
      routeContext.buildResponse(
        #ok,
        #json(responseJson),
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

    func getRepo(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
      let ?didText = routeContext.getQueryParam("did") else return routeContext.buildResponse(
        #badRequest,
        #error(#message("Missing required query parameter: did")),
      );
      let did = switch (DID.Plc.fromText(didText)) {
        case (#ok(did)) did;
        case (#err(e)) return routeContext.buildResponse(
          #badRequest,
          #error(#message("Invalid did: " # e)),
        );
      };

      let sinceOrNull : ?TID.TID = switch (routeContext.getQueryParam("since")) {
        case (null) null;
        case (?sinceText) switch (TID.fromText(sinceText)) {
          case (#ok(tid)) ?tid;
          case (#err(e)) return routeContext.buildResponse(
            #badRequest,
            #error(#message("Invalid 'since' parameter, must be a valid TID: " # e)),
          );
        };
      };

      let serverInfo = serverInfoHandler.get();
      if (did != serverInfo.plcIdentifier) {
        return routeContext.buildResponse(
          #notFound,
          #error(#message("Repository not found: " # didText)),
        );
      };

      let repository = repositoryHandler.get();

      let exportDataKind = switch (sinceOrNull) {
        case (null) #full({ includeHistorical = false });
        case (?since) #since(since);
      };

      let carFile = switch (CarUtil.fromRepository(repository, exportDataKind)) {
        case (#ok(blob)) blob;
        case (#err(e)) return routeContext.buildResponse(
          #badRequest,
          #error(#message("Failed to get repo as CAR: " # e)),
        );
      };

      Debug.print("Generated CAR file: " # debug_show (carFile));

      let carBlob = Blob.fromArray(CAR.toBytes(carFile));

      routeContext.buildResponse(
        #ok,
        #custom({
          headers = [
            ("Content-Type", "application/x-application/vnd.ipld.car"),
            ("Content-Disposition", "attachment; filename=\"repo.car\""),
          ];
          body = carBlob;
        }),
      );
    };

    func listBlobs(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
      let ?didText = routeContext.getQueryParam("did") else return routeContext.buildResponse(
        #badRequest,
        #error(#message("Missing required query parameter: did")),
      );
      let did = switch (DID.Plc.fromText(didText)) {
        case (#ok(did)) did;
        case (#err(e)) return routeContext.buildResponse(
          #badRequest,
          #error(#message("Invalid did: " # e)),
        );
      };

      let serverInfo = serverInfoHandler.get();
      if (did != serverInfo.plcIdentifier) {
        return routeContext.buildResponse(
          #notFound,
          #error(#message("Repository not found: " # didText)),
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
      let sinceOrNull : ?TID.TID = switch (sinceText) {
        case (null) null; // No 'since' parameter means all blobs
        case (?sinceText) switch (TID.fromText(sinceText)) {
          case (#ok(tid)) ?tid;
          case (#err(e)) return routeContext.buildResponse(
            #badRequest,
            #error(#message("Invalid 'since' parameter, must be a valid TID: " # e)),
          );
        };
      };

      let cursorTextOrNull = routeContext.getQueryParam("cursor");

      let request = {
        since = sinceOrNull;
        limit = limitOrNull;
        cursor = cursorTextOrNull;
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

    func getProfile(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
      // Parse query parameters for the actor parameter
      let ?actorParam = routeContext.getQueryParam("actor") else return routeContext.buildResponse(
        #badRequest,
        #error(#message("Missing required query parameter: actor")),
      );

      let ?profile = getProfileInternal(actorParam) else return routeContext.buildResponse(
        #notFound,
        #error(#message("Profile not found: " # actorParam)),
      );

      let responseJson = GetProfile.toJson(profile);
      routeContext.buildResponse(
        #ok,
        #json(responseJson),
      );
    };

    func getProfileInternal(idOrHandle : Text) : ?ActorDefs.ProfileViewDetailed {
      let serverInfo = serverInfoHandler.get();
      switch (DID.Plc.fromText(idOrHandle)) {
        case (#ok(did)) {
          if (did != serverInfo.plcIdentifier) return null;
        };
        case (#err(_)) {
          let prefix = ServerInfo.getPrefixFromHandle(serverInfo, idOrHandle);
          if (serverInfo.handlePrefix != prefix) return null;
        };
      };

      let recordRequest = {
        collection = "app.bsky.actor.profile";
        rkey = "self";
        cid = null;
      };

      let { avatar; displayName; description } = switch (repositoryHandler.getRecord(recordRequest)) {
        case (null) ({
          avatar = null;
          displayName = null;
          description = null;
        });
        case (?record) {
          let avatar : ?Text = switch (DagCbor.get(record.value, "avatar")) {
            case (?#text(avatarUrl)) ?avatarUrl;
            case (?#map(avatarMap)) buildAvatarUrlFromObject(avatarMap, serverInfo.plcIdentifier);
            case (null) null;
            case (_) {
              Debug.print("Invalid avatar type in profile record: " # debug_show (record.value));
              null;
            };
          };
          let displayName = switch (DagCbor.getAsNullableText(record.value, "displayName", true)) {
            case (#ok(displayName)) displayName;
            case (#err(e)) {
              Debug.print("Invalid displayName type in profile record: " # debug_show (e));
              null;
            };
          };

          let description = switch (DagCbor.getAsNullableText(record.value, "description", true)) {
            case (#ok(description)) description;
            case (#err(e)) {
              Debug.print("Invalid description type in profile record: " # debug_show (e));
              null;
            };
          };
          {
            avatar = avatar;
            displayName = displayName;
            description = description;
          };
        };
      };

      ?{
        did = serverInfo.plcIdentifier;
        handle = ServerInfo.buildHandle(serverInfo);
        avatar = avatar;
        displayName = displayName;
        banner = null; // TODO
        createdAt = null; // TODO
        description = description;
        followersCount = null; // TODO
        followsCount = null; // TODO
        indexedAt = null; // TODO
        labels = []; // TODO
        postsCount = null; // TODO
        associated = null; // TODO
        joinedViaStarterPack = null; // TODO
        pinnedPost = null; // TODO
        status = null; // TODO
        verification = null; // TODO
        viewer = null; // TODO
      };
    };

    func buildAvatarUrlFromObject(
      avatarMap : [(Text, DagCbor.Value)],
      actorId : DID.Plc.DID,
    ) : ?Text {
      let type_ = switch (DagCbor.getAsText(#map(avatarMap), "$type")) {
        case (#ok(type_)) type_;
        case (#err(e)) {
          Debug.print("Invalid avatar type in profile record: " # debug_show (e));
          return null;
        };
      };
      if (type_ != "blob") {
        Debug.print("Unsupported avatar type in profile record: " # debug_show (type_));
        return null;
      };
      let cidText = switch (DagCbor.getAsText(#map(avatarMap), "ref.$link")) {
        case (#ok(cid)) cid;
        case (#err(e)) {
          Debug.print("Invalid avatar ref type in profile record: " # debug_show (e));
          return null;
        };
      };
      let mimeType = switch (DagCbor.getAsText(#map(avatarMap), "mimeType")) {
        case (#ok(mimeType)) mimeType;
        case (#err(e)) {
          Debug.print("Invalid avatar type in profile record: " # debug_show (e));
          return null;
        };
      };

      let ?imageType = Text.stripStart(mimeType, #text("image/")) else {
        Debug.print("Invalid avatar mimeType in profile record, expected image/*: " # debug_show (mimeType));
        return null;
      };
      let actorIdText = DID.Plc.toText(actorId);
      ?("https://cdn.bsky.app/img/avatar/plain/" # actorIdText # "/" # cidText # "@" # imageType);
    };

    func getProfiles(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
      // Parse query parameter: actors (comma-separated)
      let ?actorsParam = routeContext.getQueryParam("actors") else return routeContext.buildResponse(
        #badRequest,
        #error(#message("Missing required query parameter: actors")),
      );
      let actors = Text.split(actorsParam, #char(','));

      let profiles = DynamicArray.DynamicArray<ActorDefs.ProfileViewDetailed>(25);
      for (actor_ in actors) {
        let trimmedActor = TextX.trimWhitespace(actor_);
        let ?profile = getProfileInternal(trimmedActor) else return routeContext.buildResponse(
          #notFound,
          #error(#message("Profile not found: " # trimmedActor)),
        );
        profiles.add(profile);
      };
      if (profiles.size() > 25) return routeContext.buildResponse(
        #badRequest,
        #error(#message("Too many actors (max 25)")),
      );

      let responseJson = GetProfiles.toJson({
        profiles = DynamicArray.toArray(profiles);
      });
      routeContext.buildResponse(
        #ok,
        #json(responseJson),
      );
    };

    func resolveHandle(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
      // Parse query parameters for the handle parameter
      let ?handleParam = routeContext.getQueryParam("handle") else return routeContext.buildResponse(
        #badRequest,
        #error(#message("Missing required query parameter: handle")),
      );
      let serverInfo = serverInfoHandler.get();

      let prefix = ServerInfo.getPrefixFromHandle(serverInfo, handleParam);

      if (serverInfo.handlePrefix != prefix) return routeContext.buildResponse(
        #notFound,
        #error(#message("Handle not found: " # handleParam)),
      );

      let response : ResolveHandle.Response = {
        did = serverInfo.plcIdentifier;
      };

      let responseJson = ResolveHandle.toJson(response);
      routeContext.buildResponse(
        #ok,
        #json(responseJson),
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
