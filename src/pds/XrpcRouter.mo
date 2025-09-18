import Text "mo:core@1/Text";
import Array "mo:core@1/Array";
import Repository "./Types/Repository";
import RepositoryHandler "Handlers/RepositoryHandler";
import ServerInfoHandler "Handlers/ServerInfoHandler";
import AccountHandler "Handlers/AccountHandler";
import BskyHandler "Handlers/BskyHandler";
import RouteContext "mo:liminal@1/RouteContext";
import Route "mo:liminal@1/Route";
import Serde "mo:serde";
import DID "mo:did@3";
import Domain "mo:url-kit@3/Domain";
import CID "mo:cid@1";
import TID "mo:tid@1";
import Json "mo:json@1";
import Result "mo:core@1/Result";
import Nat "mo:core@1/Nat";
import TextX "mo:xtended-text@2/TextX";
import DescribeRepo "./Types/Lexicons/Com/Atproto/Repo/DescribeRepo";
import CreateRecord "./Types/Lexicons/Com/Atproto/Repo/CreateRecord";
import GetRecord "./Types/Lexicons/Com/Atproto/Repo/GetRecord";
import PutRecord "./Types/Lexicons/Com/Atproto/Repo/PutRecord";
import DeleteRecord "./Types/Lexicons/Com/Atproto/Repo/DeleteRecord";
import UploadBlob "./Types/Lexicons/Com/Atproto/Repo/UploadBlob";
import ListBlobs "./Types/Lexicons/Com/Atproto/Sync/ListBlobs";
import CreateSession "./Types/Lexicons/Com/Atproto/Server/CreateSession";
import GetSession "./Types/Lexicons/Com/Atproto/Server/GetSession";
import CreateAccount "./Types/Lexicons/Com/Atproto/Server/CreateAccount";
import ApplyWrites "./Types/Lexicons/Com/Atproto/Repo/ApplyWrites";
import GetProfile "./Types/Lexicons/App/Bsky/Actor/GetProfile";
import GetProfiles "./Types/Lexicons/App/Bsky/Actor/GetProfiles";
import GetPreferences "./Types/Lexicons/App/Bsky/Actor/GetPreferences";
import PutPreferences "./Types/Lexicons/App/Bsky/Actor/PutPreferences";
import GetServices "./Types/Lexicons/App/Bsky/Labeler/GetServices";
import ActorDefs "./Types/Lexicons/App/Bsky/Actor/Defs";
import ResolveHandle "./Types/Lexicons/Com/Atproto/Identity/ResolveHandle";
import DynamicArray "mo:xtended-collections@0/DynamicArray";
import Runtime "mo:core@1/Runtime";
import ServerInfo "Types/ServerInfo";
import DagCbor "mo:dag-cbor@2";

module {

  public class Router(
    repositoryHandler : RepositoryHandler.Handler,
    serverInfoHandler : ServerInfoHandler.Handler,
    accountHandler : AccountHandler.Handler,
    bskyHandler : BskyHandler.Handler,
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
        case ("com.atproto.server.createaccount") await* createAccount(routeContext);
        case ("com.atproto.server.createsession") await* createSession(routeContext);
        case ("com.atproto.server.getsession") await* getSession(routeContext);
        case ("com.atproto.server.describeserver") describeServer(routeContext);
        case ("com.atproto.sync.listblobs") listBlobs(routeContext);
        case ("com.atproto.sync.listrepos") listRepos(routeContext);
        case ("com.atproto.identity.resolvehandle") resolveHandle(routeContext);
        case ("app.bsky.actor.getprofile") getProfile(routeContext);
        case ("app.bsky.actor.getprofiles") getProfiles(routeContext);
        case ("app.bsky.actor.getpreferences") getPreferences(routeContext);
        case ("app.bsky.actor.putpreferences") putPreferences(routeContext);
        case ("app.bsky.labeler.getservices") getServices(routeContext);
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
          #badRequest, // TODO
          #error(#message("Failed to apply writes: " # e)),
        );
      };

      let responseJson = ApplyWrites.toJson(response);
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

      let contactCandid = switch (serverInfo.contactEmailAddress) {
        case (null) [];
        case (?email) [
          ("email", #Text(email)),
        ];
      };

      routeContext.buildResponse(
        #ok,
        #content(
          #Record([
            ("did", #Text(DID.Plc.toText(serverInfo.plcDid))),
            ("availableUserDomains", #Array([#Text("." # serverInfo.hostname)])),
            ("inviteCodeRequired", #Bool(true)),
            ("links", #Record(linksCandid)),
            ("contact", #Record(contactCandid)),
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

      let responseJson = GetRecord.toJson(response);
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

      let cursorTextOrNull = routeContext.getQueryParam("cursor");

      let request : ListBlobs.Request = {
        did = did;
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

    func getSession(routeContext : RouteContext.RouteContext) : async* Route.HttpResponse {
      let ?actorId = getRequestActorId(routeContext) else return routeContext.buildResponse(
        #unauthorized,
        #empty,
      );

      // Get session info from the account handler
      let response = switch (await* accountHandler.getSession(actorId)) {
        case (#ok(response)) response;
        case (#err(e)) return routeContext.buildResponse(
          #unauthorized,
          #error(#message("Failed to get session: " # e)),
        );
      };

      let responseJson = GetSession.toJson(response);
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
      let account = switch (DID.Plc.fromText(idOrHandle)) {
        case (#ok(did)) switch (accountHandler.get(did)) {
          case (?account) account;
          case (null) return null;
        };
        case (#err(_)) {
          let ?name = ServerInfo.getAccountNameFromHandle(serverInfo, idOrHandle) else return null;
          switch (accountHandler.getByName(name)) {
            case (?account) account;
            case (null) return null;
          };
        };
      };

      let recordRequest : GetRecord.Request = {
        repo = account.id;
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
          let #ok(avatar) = DagCbor.getAsNullableText(record.value, "avatar", true) else Runtime.trap("Invalid avatar type in profile record");
          let #ok(displayName) = DagCbor.getAsNullableText(record.value, "displayName", true) else Runtime.trap("Invalid displayName type in profile record");
          let #ok(description) = DagCbor.getAsNullableText(record.value, "description", true) else Runtime.trap("Invalid description type in profile record");
          {
            avatar = avatar;
            displayName = displayName;
            description = description;
          };
        };
      };

      ?{
        did = account.id;
        handle = ServerInfo.buildHandleFromAccountName(serverInfo, account.name);
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

    func getPreferences(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
      let ?actorId = getRequestActorId(routeContext) else return routeContext.buildResponse(
        #unauthorized,
        #empty,
      );
      let preferences = bskyHandler.getPreferences(actorId);
      let preferenceItems = DynamicArray.DynamicArray<ActorDefs.PreferenceItem>(16);

      switch (preferences.adultContent) {
        case (null) ();
        case (?p) preferenceItems.add(#adultContentPref(p));
      };
      switch (preferences.contentLabel) {
        case (null) ();
        case (?p) preferenceItems.add(#contentLabelPref(p));
      };
      switch (preferences.savedFeeds) {
        case (null) ();
        case (?p) preferenceItems.add(#savedFeedsPref(p));
      };
      switch (preferences.savedFeedsV2) {
        case (null) ();
        case (?p) preferenceItems.add(#savedFeedsPrefV2(p));
      };
      switch (preferences.personalDetails) {
        case (null) ();
        case (?p) preferenceItems.add(#personalDetailsPref(p));
      };
      switch (preferences.feedView) {
        case (null) ();
        case (?p) preferenceItems.add(#feedViewPref(p));
      };
      switch (preferences.threadView) {
        case (null) ();
        case (?p) preferenceItems.add(#threadViewPref(p));
      };
      switch (preferences.interests) {
        case (null) ();
        case (?p) preferenceItems.add(#interestsPref(p));
      };
      switch (preferences.mutedWords) {
        case (null) ();
        case (?p) preferenceItems.add(#mutedWordsPref(p));
      };
      switch (preferences.hiddenPosts) {
        case (null) ();
        case (?p) preferenceItems.add(#hiddenPostsPref(p));
      };
      switch (preferences.bskyAppState) {
        case (null) ();
        case (?p) preferenceItems.add(#bskyAppStatePref(p));
      };
      switch (preferences.labelers) {
        case (null) ();
        case (?p) preferenceItems.add(#labelersPref(p));
      };
      switch (preferences.postInteractionSettings) {
        case (null) ();
        case (?p) preferenceItems.add(#postInteractionSettingsPref(p));
      };
      switch (preferences.verification) {
        case (null) ();
        case (?p) preferenceItems.add(#verificationPrefs(p));
      };

      let response : GetPreferences.Response = {
        preferences = DynamicArray.toArray(preferenceItems);
      };

      let responseJson = GetPreferences.toJson(response);
      routeContext.buildResponse(
        #ok,
        #json(responseJson),
      );
    };

    func putPreferences(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
      let ?actorId = getRequestActorId(routeContext) else return routeContext.buildResponse(
        #unauthorized,
        #empty,
      );
      let request = switch (parseRequestFromBody(routeContext, PutPreferences.fromJson)) {
        case (#ok(req)) req;
        case (#err(e)) return routeContext.buildResponse(
          #badRequest,
          #error(#message(e)),
        );
      };
      bskyHandler.putPreferences(actorId, request.preferences);
      routeContext.buildResponse(
        #ok,
        #empty,
      );
    };

    func getServices(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
      // TODO
      // Parse query parameters
      // let ?didsParam = routeContext.getQueryParam("dids") else return routeContext.buildResponse(
      //   #badRequest,
      //   #error(#message("Missing required query parameter: dids")),
      // );

      // let detailed = switch (routeContext.getQueryParam("detailed")) {
      //   case (null) ?false;
      //   case (?detailedText) switch (Text.toLower(detailedText)) {
      //     case ("true" or "" or "1") ?true; // TODO bool parser?
      //     case ("false" or "0") ?false;
      //     case (_) return routeContext.buildResponse(
      //       #badRequest,
      //       #error(#message("Invalid detailed parameter, expected 'true' or 'false'")),
      //     );
      //   };
      // };

      // // Split DIDs by comma
      // let dids = Text.split(didsParam, #char(','));
      // let didsArray = Array.fromIter(dids);

      // TODO: Implement actual labeler service lookup
      let mockViews : [GetServices.LabelerViewUnion] = [];

      let response : GetServices.Response = {
        views = mockViews;
      };

      let responseJson = GetServices.toJson(response);
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

      let ?name = ServerInfo.getAccountNameFromHandle(serverInfo, handleParam) else return routeContext.buildResponse(
        #notFound,
        #error(#message("Handle not found: " # handleParam)),
      );

      // Resolve handle to DID using AccountHandler
      let account = switch (accountHandler.getByName(name)) {
        case (?account) account;
        case (null) return routeContext.buildResponse(
          #notFound,
          #error(#message("Handle not found: " # handleParam)),
        );
      };

      let response : ResolveHandle.Response = {
        did = account.id;
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

    func getRequestActorId(routeContext : RouteContext.RouteContext) : ?DID.Plc.DID {
      switch (routeContext.getIdentity()) {
        case (null) null;
        case (?identity) switch (identity.getId()) {
          case (null) null;
          case (?id) switch (DID.Plc.fromText(id)) {
            case (#ok(did)) ?did;
            case (#err(_)) null; // Invalid DID in identity
          };
        };
      };
    };
  };
};
