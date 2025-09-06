import Repository "../Types/Repository";
import DID "mo:did@2";
import CID "mo:cid@1";
import TID "mo:tid@1";
import PureMap "mo:core@1/pure/Map";
import Commit "../Types/Commit";
import DagCbor "mo:dag-cbor@2";
import MST "../Types/MST";
import CIDBuilder "../CIDBuilder";
import AtUri "../Types/AtUri";
import Result "mo:base/Result";
import KeyHandler "../Handlers/KeyHandler";
import Text "mo:core@1/Text";
import Order "mo:core@1/Order";
import Blob "mo:core@1/Blob";
import MSTHandler "../Handlers/MSTHandler";
import Iter "mo:core@1/Iter";
import LexiconValidator "../LexiconValidator";
import Debug "mo:core@1/Debug";
import ServerInfoHandler "./ServerInfoHandler";
import Domain "mo:url-kit/Domain";
import DIDModule "../DID";
import Nat "mo:core@1/Nat";
import Array "mo:core@1/Array";
import DescribeRepo "../Types/Lexicons/Com/Atproto/Repo/DescribeRepo";
import CreateRecord "../Types/Lexicons/Com/Atproto/Repo/CreateRecord";
import GetRecord "../Types/Lexicons/Com/Atproto/Repo/GetRecord";
import PutRecord "../Types/Lexicons/Com/Atproto/Repo/PutRecord";
import DeleteRecord "../Types/Lexicons/Com/Atproto/Repo/DeleteRecord";
import ListRecords "../Types/Lexicons/Com/Atproto/Repo/ListRecords";
import UploadBlob "../Types/Lexicons/Com/Atproto/Repo/UploadBlob";
import ImportRepo "../Types/Lexicons/Com/Atproto/Repo/ImportRepo";
import RepoCommon "../Types/Lexicons/Com/Atproto/Repo/Common";
import ListBlobs "../Types/Lexicons/Com/Atproto/Sync/ListBlobs";
import BlobRef "../Types/BlobRef";
import Time "mo:core@1/Time";
import ApplyWrites "../Types/Lexicons/Com/Atproto/Repo/ApplyWrites";
import List "mo:core@1/List";
import Runtime "mo:core@1/Runtime";
import Int "mo:core@1/Int";

module {
  public type StableData = {
    repositories : PureMap.Map<DID.Plc.DID, RepositoryWithData>;
    blobs : PureMap.Map<CID.CID, BlobWithMetaData>;
  };

  type Commit = {
    did : DID.Plc.DID;
    version : Nat;
    data : CID.CID;
    prev : ?CID.CID;
    sig : Blob;
  };

  public type RepositoryWithData = Repository.RepositoryWithoutDID and {
    commits : PureMap.Map<TID.TID, Commit>;
    records : PureMap.Map<CID.CID, DagCbor.Value>;
    nodes : PureMap.Map<Text, MST.Node>;
    blobs : PureMap.Map<CID.CID, BlobRef.BlobRef>;
  };

  public type BlobWithMetaData = {
    data : Blob;
    mimeType : Text;
    createdAt : Time.Time;
  };

  public class Handler(
    stableData : StableData,
    keyHandler : KeyHandler.Handler,
    tidGenerator : TID.Generator,
    serverInfoHandler : ServerInfoHandler.Handler,
  ) {
    var repositories = stableData.repositories;
    var blobs = stableData.blobs;

    public func getAll(limit : Nat) : [Repository.Repository] {
      return PureMap.entries(repositories)
      |> Iter.take(_, limit)
      |> Iter.map(
        _,
        func((did, repo) : (DID.Plc.DID, RepositoryWithData)) : Repository.Repository {
          {
            repo with
            did = did;
          };
        },
      )
      |> Iter.toArray(_);
    };

    public func get(id : DID.Plc.DID) : ?Repository.Repository {
      let ?repo = PureMap.get(repositories, DIDModule.comparePlcDID, id) else return null;
      ?{
        repo with
        did = id;
      };
    };

    public func describe(request : DescribeRepo.Request) : async* Result.Result<DescribeRepo.Response, Text> {
      let ?repo = PureMap.get(repositories, DIDModule.comparePlcDID, request.repo) else return #err("Repository not found: " # DID.Plc.toText(request.repo));

      let mstHandler = MSTHandler.Handler(repo.nodes);

      let collections = mstHandler.getAllCollections();

      let ?serverInfo = serverInfoHandler.get() else return #err("Server not initialized");

      let handle = Domain.toText(serverInfo.domain);

      let verificationKey : DID.Key.DID = switch (await* keyHandler.getPublicKey(#verification)) {
        case (#ok(did)) did;
        case (#err(e)) return #err("Failed to get verification public key: " # e);
      };
      let webDid : DID.Web.DID = {
        host = #domain(serverInfo.domain);
        path = [];
        port = null;
      };

      let didDoc = DIDModule.generateDIDDocument(request.repo, webDid, verificationKey);

      let handleIsCorrect = true; // TODO?

      #ok({
        handle = handle;
        did = request.repo;
        didDoc = didDoc;
        collections = collections;
        handleIsCorrect = handleIsCorrect;
      });
    };

    public func create(
      id : DID.Plc.DID
    ) : async* Result.Result<Repository.Repository, Text> {

      let mstHandler = MSTHandler.Handler(PureMap.empty<Text, MST.Node>());
      // First node is empty
      let newMST : MST.Node = {
        leftSubtreeCID = null;
        entries = [];
      };
      let rev = tidGenerator.next();
      let newMSTCID = mstHandler.addNode(newMST);
      let signedCommit = switch (await* createCommit(id, rev, newMSTCID, null)) {
        case (#ok(commit)) commit;
        case (#err(e)) return #err("Failed to create commit: " # e);
      };
      let signedCommitCID = CIDBuilder.fromCommit(signedCommit);
      let newRepo : RepositoryWithData = {
        head = signedCommitCID;
        rev = rev;
        active = true;
        status = null;
        commits = PureMap.singleton<TID.TID, Commit>(rev, signedCommit);
        records = PureMap.empty<CID.CID, DagCbor.Value>();
        nodes = mstHandler.getNodes();
        blobs = PureMap.empty<CID.CID, BlobRef.BlobRef>();
      };
      let (newRepositories, isNewKey) = PureMap.insert(
        repositories,
        DIDModule.comparePlcDID,
        id,
        newRepo,
      );
      if (not isNewKey) {
        return #err("Repository with DID " # DID.Plc.toText(id) # " already exists");
      };
      repositories := newRepositories;
      #ok({
        newRepo with
        did = id;
      });
    };

    public func createRecord(
      request : CreateRecord.Request
    ) : async* Result.Result<CreateRecord.Response, Text> {

      let ?repo = PureMap.get(repositories, DIDModule.comparePlcDID, request.repo) else return #err("Repository not found: " # DID.Plc.toText(request.repo));

      let rKey : Text = switch (request.rkey) {
        case (?rkey) {
          if (Text.size(rkey) > 512) {
            return #err("Record key exceeds maximum length of 512 characters");
          };
          rkey;
        };
        case (null) TID.toText(tidGenerator.next());
      };

      switch (request.swapCommit) {
        case (?_) {
          // Handle swapCommit field
          Debug.todo();
        };
        case (null) ();
      };

      let validationResult : Result.Result<RepoCommon.ValidationStatus, Text> = switch (request.validate) {
        case (?true) LexiconValidator.validateRecord(request.record, request.collection, false);
        case (?false) #ok(#unknown);
        case (null) LexiconValidator.validateRecord(request.record, request.collection, true);
      };
      let validationStatus = switch (validationResult) {
        case (#ok(status)) status;
        case (#err(e)) return #err("Record validation failed: " # e);
      };

      let recordCID = CIDBuilder.fromRecord(rKey, request.record);
      let updatedRecords = PureMap.add(repo.records, compareCID, recordCID, request.record);

      // Create record path
      let path = AtUri.toText({
        repoId = request.repo;
        collectionAndRecord = ?(request.collection, ?rKey);
      });
      let pathKey = MST.pathToKey(path);

      let mstHandler = MSTHandler.Handler(repo.nodes);

      // Get current MST root from the latest commit
      let ?currentCommit = PureMap.get<TID.TID, Commit>(
        repo.commits,
        TID.compare,
        repo.rev,
      ) else return #err("No commits found in repository");

      let currentNodeCID = currentCommit.data;

      // Add to MST
      let newNode = switch (mstHandler.addCID(currentCommit.data, pathKey, recordCID)) {
        case (#ok(mst)) mst;
        case (#err(e)) return #err("Failed to add to MST: " # debug_show (e));
      };

      let newNodeCID = CIDBuilder.fromMSTNode(newNode);
      // Create new commit
      let newRev = tidGenerator.next();

      let signedCommit = switch (
        await* createCommit(
          request.repo,
          newRev,
          newNodeCID,
          ?currentNodeCID,
        )
      ) {
        case (#ok(commit)) commit;
        case (#err(e)) return #err("Failed to create commit: " # e);
      };

      // Store new state
      let commitCID = CIDBuilder.fromCommit(signedCommit);
      let updatedCommits = PureMap.add<TID.TID, Commit>(
        repo.commits,
        TID.compare,
        newRev,
        signedCommit,
      );

      repositories := PureMap.add(
        repositories,
        DIDModule.comparePlcDID,
        request.repo,
        {
          repo with
          head = commitCID;
          rev = newRev;
          commits = updatedCommits;
          records = updatedRecords;
          nodes = mstHandler.getNodes();
        },
      );

      #ok({
        cid = recordCID;
        commit = ?{
          cid = commitCID;
          rev = newRev;
        };
        uri = {
          repoId = request.repo;
          collectionAndRecord = ?(request.collection, ?rKey);
        };
        validationStatus = validationStatus;
      });
    };

    public func getRecord(request : GetRecord.Request) : Result.Result<GetRecord.Response, Text> {
      let ?repo = PureMap.get(repositories, DIDModule.comparePlcDID, request.repo) else return #err("Repository not found: " # DID.Plc.toText(request.repo));

      let path = request.collection # "/" # request.rkey;
      let pathKey = MST.pathToKey(path);

      let mstHandler = MSTHandler.Handler(repo.nodes);

      // Get the current commit to find the MST root
      let ?currentCommit = PureMap.get(repo.commits, TID.compare, repo.rev) else return #err("No commits found in repository");

      // Get the root MST node from the commit's data field
      let ?rootNode = mstHandler.getNode(currentCommit.data) else return #err("Failed to get root node from MST");

      let ?recordCID = mstHandler.getCID(rootNode, pathKey) else return #err("Record not found at path: " # path);
      let ?value = PureMap.get(repo.records, compareCID, recordCID) else return #err("Record not found at path: " # path);
      #ok({
        cid = ?recordCID;
        uri = {
          repoId = request.repo;
          collectionAndRecord = ?(request.collection, ?request.rkey);
        };
        value = value;
      });
    };

    public func putRecord(request : PutRecord.Request) : async* Result.Result<PutRecord.Response, Text> {
      let ?repo = PureMap.get(repositories, DIDModule.comparePlcDID, request.repo) else return #err("Repository not found: " # DID.Plc.toText(request.repo));

      if (Text.size(request.rkey) > 512) {
        return #err("Record key exceeds maximum length of 512 characters");
      };

      switch (request.swapCommit) {
        case (?_) {
          // Handle swapCommit field
          Debug.todo();
        };
        case (null) ();
      };

      switch (request.swapRecord) {
        case (?_) {
          // Handle swapRecord field
          Debug.todo();
        };
        case (null) ();
      };

      let validationResult : Result.Result<RepoCommon.ValidationStatus, Text> = switch (request.validate) {
        case (?true) LexiconValidator.validateRecord(request.record, request.collection, false);
        case (?false) #ok(#unknown);
        case (null) LexiconValidator.validateRecord(request.record, request.collection, true);
      };
      let validationStatus = switch (validationResult) {
        case (#ok(status)) status;
        case (#err(e)) return #err("Record validation failed: " # e);
      };

      let recordCID = CIDBuilder.fromRecord(request.rkey, request.record);
      let updatedRecords = PureMap.add(repo.records, compareCID, recordCID, request.record);

      // Create record path
      let path = request.collection # "/" # request.rkey;
      let pathKey = MST.pathToKey(path);

      let mstHandler = MSTHandler.Handler(repo.nodes);

      // Get current MST root from the latest commit
      let ?currentCommit = PureMap.get<TID.TID, Commit>(
        repo.commits,
        TID.compare,
        repo.rev,
      ) else return #err("No commits found in repository");

      let currentNodeCID = currentCommit.data;

      // Update MST (this will replace existing record or add new one)
      let newNode = switch (mstHandler.addCID(currentCommit.data, pathKey, recordCID)) {
        case (#ok(mst)) mst;
        case (#err(e)) return #err("Failed to update MST: " # debug_show (e));
      };

      let newNodeCID = CIDBuilder.fromMSTNode(newNode);
      // Create new commit
      let newRev = tidGenerator.next();

      let signedCommit = switch (
        await* createCommit(
          request.repo,
          newRev,
          newNodeCID,
          ?currentNodeCID,
        )
      ) {
        case (#ok(commit)) commit;
        case (#err(e)) return #err("Failed to create commit: " # e);
      };

      // Store new state
      let commitCID = CIDBuilder.fromCommit(signedCommit);
      let updatedCommits = PureMap.add<TID.TID, Commit>(
        repo.commits,
        TID.compare,
        newRev,
        signedCommit,
      );

      repositories := PureMap.add(
        repositories,
        DIDModule.comparePlcDID,
        request.repo,
        {
          repo with
          head = commitCID;
          rev = newRev;
          commits = updatedCommits;
          records = updatedRecords;
          nodes = mstHandler.getNodes();
        },
      );

      #ok({
        cid = recordCID;
        commit = ?{
          cid = commitCID;
          rev = newRev;
        };
        uri = {
          repoId = request.repo;
          collectionAndRecord = ?(request.collection, ?request.rkey);
        };
        validationStatus = ?validationStatus;
      });
    };

    public func deleteRecord(request : DeleteRecord.Request) : async* Result.Result<DeleteRecord.Response, Text> {
      let ?repo = PureMap.get(repositories, DIDModule.comparePlcDID, request.repo) else return #err("Repository not found: " # DID.Plc.toText(request.repo));

      switch (request.swapCommit) {
        case (?_) {
          // Handle swapCommit field
          Debug.todo();
        };
        case (null) ();
      };

      switch (request.swapRecord) {
        case (?_) {
          // Handle swapRecord field
          Debug.todo();
        };
        case (null) ();
      };

      // Create record path
      let path = request.collection # "/" # request.rkey;
      let pathKey = MST.pathToKey(path);

      let mstHandler = MSTHandler.Handler(repo.nodes);

      // Get current MST root from the latest commit
      let ?currentCommit = PureMap.get<TID.TID, Commit>(
        repo.commits,
        TID.compare,
        repo.rev,
      ) else return #err("No commits found in repository");

      let currentNodeCID = currentCommit.data;

      // Check if record exists before trying to delete
      let ?rootNode = mstHandler.getNode(currentCommit.data) else return #err("Failed to get root node from MST");
      let ?_ = mstHandler.getCID(rootNode, pathKey) else return #err("Record not found at path: " # path);

      // Remove from MST
      let newNode = switch (mstHandler.removeCID(currentCommit.data, pathKey)) {
        case (#ok(mst)) mst;
        case (#err(e)) return #err("Failed to remove from MST: " # debug_show (e));
      };

      let newNodeCID = CIDBuilder.fromMSTNode(newNode);
      // Create new commit
      let newRev = tidGenerator.next();

      let signedCommit = switch (
        await* createCommit(
          request.repo,
          newRev,
          newNodeCID,
          ?currentNodeCID,
        )
      ) {
        case (#ok(commit)) commit;
        case (#err(e)) return #err("Failed to create commit: " # e);
      };

      // Store new state
      let commitCID = CIDBuilder.fromCommit(signedCommit);
      let updatedCommits = PureMap.add<TID.TID, Commit>(
        repo.commits,
        TID.compare,
        newRev,
        signedCommit,
      );

      repositories := PureMap.add(
        repositories,
        DIDModule.comparePlcDID,
        request.repo,
        {
          repo with
          head = commitCID;
          rev = newRev;
          commits = updatedCommits;
          nodes = mstHandler.getNodes();
        },
      );

      #ok({
        commit = ?{
          cid = commitCID;
          rev = newRev;
        };
      });
    };

    public func applyWrites(request : ApplyWrites.Request) : async* Result.Result<ApplyWrites.Response, Text> {
      let ?repo = PureMap.get(repositories, DIDModule.comparePlcDID, request.repo) else return #err("Repository not found: " # DID.Plc.toText(request.repo));

      // Check swap commit if provided
      switch (request.swapCommit) {
        case (?_) {
          // TODO
          return #err("Swap commit not implemented yet");
        };
        case (null) ();
      };

      var updatedRecords = repo.records;
      var updatedBlobs = repo.blobs;
      let mstHandler = MSTHandler.Handler(repo.nodes);
      var currentNodeCID = repo.head;

      // Get current MST root from the latest commit
      let ?currentCommit = PureMap.get<TID.TID, Commit>(
        repo.commits,
        TID.compare,
        repo.rev,
      ) else return #err("No commits found in repository");

      // Process all write operations and collect results
      let results = List.empty<ApplyWrites.WriteResult>();

      for (writeOp in request.writes.vals()) {
        let result = switch (writeOp) {
          case (#create(createOp)) {
            let rKey : Text = switch (createOp.rkey) {
              case (?rkey) {
                if (Text.size(rkey) > 512) {
                  return #err("Record key exceeds maximum length of 512 characters");
                };
                rkey;
              };
              case (null) TID.toText(tidGenerator.next());
            };

            // Validate record
            let validationResult : Result.Result<RepoCommon.ValidationStatus, Text> = switch (request.validate) {
              case (?true) LexiconValidator.validateRecord(createOp.value, createOp.collection, false);
              case (?false) #ok(#unknown);
              case (null) LexiconValidator.validateRecord(createOp.value, createOp.collection, true);
            };
            let validationStatus = switch (validationResult) {
              case (#ok(status)) status;
              case (#err(e)) return #err("Record validation failed: " # e);
            };

            let recordCID = CIDBuilder.fromRecord(rKey, createOp.value);
            updatedRecords := PureMap.add(updatedRecords, compareCID, recordCID, createOp.value);

            // Create record path for MST
            let path = createOp.collection # "/" # rKey;
            let pathKey = MST.pathToKey(path);

            // Add to MST
            let newNode = switch (mstHandler.addCID(currentCommit.data, pathKey, recordCID)) {
              case (#ok(mst)) mst;
              case (#err(e)) return #err("Failed to add to MST: " # debug_show (e));
            };

            currentNodeCID := CIDBuilder.fromMSTNode(newNode);

            #create({
              uri = {
                repoId = request.repo;
                collectionAndRecord = ?(createOp.collection, ?rKey);
              };
              cid = recordCID;
              validationStatus = validationStatus;
            });
          };
          case (#update(updateOp)) {
            if (Text.size(updateOp.rkey) > 512) {
              return #err("Record key exceeds maximum length of 512 characters");
            };

            // Validate record
            let validationResult : Result.Result<RepoCommon.ValidationStatus, Text> = switch (request.validate) {
              case (?true) LexiconValidator.validateRecord(updateOp.value, updateOp.collection, false);
              case (?false) #ok(#unknown);
              case (null) LexiconValidator.validateRecord(updateOp.value, updateOp.collection, true);
            };
            let validationStatus = switch (validationResult) {
              case (#ok(status)) status;
              case (#err(e)) return #err("Record validation failed: " # e);
            };

            let recordCID = CIDBuilder.fromRecord(updateOp.rkey, updateOp.value);
            updatedRecords := PureMap.add(updatedRecords, compareCID, recordCID, updateOp.value);

            // Create record path for MST
            let path = updateOp.collection # "/" # updateOp.rkey;
            let pathKey = MST.pathToKey(path);

            // Update MST (this will replace existing record)
            let newNode = switch (mstHandler.addCID(currentNodeCID, pathKey, recordCID)) {
              case (#ok(mst)) mst;
              case (#err(e)) return #err("Failed to update MST: " # debug_show (e));
            };

            currentNodeCID := CIDBuilder.fromMSTNode(newNode);

            #update({
              uri = {
                repoId = request.repo;
                collectionAndRecord = ?(updateOp.collection, ?updateOp.rkey);
              };
              cid = recordCID;
              validationStatus = validationStatus;
            });
          };
          case (#delete(deleteOp)) {
            // Create record path for MST
            let path = deleteOp.collection # "/" # deleteOp.rkey;
            let pathKey = MST.pathToKey(path);

            // Check if record exists before trying to delete
            let ?rootNode = mstHandler.getNode(currentNodeCID) else return #err("Failed to get root node from MST");
            let ?_ = mstHandler.getCID(rootNode, pathKey) else return #err("Record not found at path: " # path);

            // Remove from MST
            let newNode = switch (mstHandler.removeCID(currentNodeCID, pathKey)) {
              case (#ok(mst)) mst;
              case (#err(e)) return #err("Failed to remove from MST: " # debug_show (e));
            };

            currentNodeCID := CIDBuilder.fromMSTNode(newNode);

            #delete({});
          };
        };
        List.add(results, result);
      };

      // Create single commit for all operations
      let newRev = tidGenerator.next();
      let signedCommit = switch (
        await* createCommit(
          request.repo,
          newRev,
          currentNodeCID,
          ?currentCommit.data,
        )
      ) {
        case (#ok(commit)) commit;
        case (#err(e)) return #err("Failed to create commit: " # e);
      };

      // Store new state
      let commitCID = CIDBuilder.fromCommit(signedCommit);
      let updatedCommits = PureMap.add<TID.TID, Commit>(
        repo.commits,
        TID.compare,
        newRev,
        signedCommit,
      );

      repositories := PureMap.add(
        repositories,
        DIDModule.comparePlcDID,
        request.repo,
        {
          repo with
          head = commitCID;
          rev = newRev;
          commits = updatedCommits;
          records = updatedRecords;
          nodes = mstHandler.getNodes();
          blobs = updatedBlobs;
        },
      );

      #ok({
        commit = ?{
          cid = commitCID;
          rev = newRev;
        };
        results = List.toArray(results);
      });
    };

    public func listRecords(request : ListRecords.Request) : Result.Result<ListRecords.Response, Text> {
      let ?repo = PureMap.get(repositories, DIDModule.comparePlcDID, request.repo) else return #err("Repository not found: " # DID.Plc.toText(request.repo));

      let mstHandler = MSTHandler.Handler(repo.nodes);

      // TODO optimize for reverse/limit/cursor
      let collectionRecords = mstHandler.getCollectionRecords(request.collection);

      // Convert to ListRecord format
      let records = collectionRecords
      |> Array.map<(key : Text, CID.CID), ListRecords.ListRecord>(
        _,
        func((key, cid) : (key : Text, CID.CID)) : ListRecords.ListRecord {
          let ?value : ?DagCbor.Value = PureMap.get(repo.records, compareCID, cid) else Runtime.trap("Record not found: " # CID.toText(cid));
          {
            uri = {
              repoId = request.repo;
              collectionAndRecord = ?(request.collection, ?key);
            };
            cid = cid;
            value = value;
          };
        },
      );

      // Apply reverse ordering if requested
      let orderedRecords = switch (request.reverse) {
        case (?true) Array.reverse(records);
        case (_) records;
      };

      // Apply pagination
      let limit = switch (request.limit) {
        case (?l) l;
        case (null) 50;
      };

      // Find start index based on cursor
      let startIndex = switch (request.cursor) {
        case (?cursor) {
          // Find the record after the cursor
          var index = 0;
          label findCursor for (record in orderedRecords.vals()) {
            let recordUri = AtUri.toText(record.uri);
            if (recordUri == cursor) {
              index += 1;
              break findCursor;
            };
            index += 1;
          };
          index;
        };
        case (null) 0;
      };

      // Get the slice of records
      let endIndex = Nat.min(startIndex + limit, orderedRecords.size());
      let resultRecords = if (startIndex >= orderedRecords.size()) {
        [];
      } else {
        Array.sliceToArray(orderedRecords, startIndex, endIndex);
      };

      // Generate next cursor
      let nextCursor = if (endIndex < orderedRecords.size()) {
        ?AtUri.toText(resultRecords[resultRecords.size() - 1].uri);
      } else {
        null;
      };

      #ok({
        cursor = nextCursor;
        records = resultRecords;
      });
    };

    public func importRepo(request : ImportRepo.Request) : Result.Result<(), Text> {

      // Parse CAR file header to get root CIDs
      let roots = request.header.roots;
      if (roots.size() == 0) {
        return #err("CAR file has no root CIDs");
      };

      // Build maps for quick lookup of blocks
      var blockMap = PureMap.empty<CID.CID, Blob>();
      for (block in request.blocks.vals()) {
        blockMap := PureMap.add(blockMap, compareCID, block.cid, block.data);
      };

      // Find the latest commit (should be first root)
      let latestCommitCID = roots[0];
      let ?latestCommitData = PureMap.get(blockMap, compareCID, latestCommitCID) else {
        return #err("Latest commit block not found");
      };

      // Decode the commit
      let latestCommit = switch (DagCbor.fromBytes(latestCommitData.vals())) {
        case (#ok(commitValue)) {
          switch (parseCommitFromCbor(commitValue)) {
            case (#ok(commit)) commit;
            case (#err(e)) return #err("Failed to parse commit: " # e);
          };
        };
        case (#err(e)) return #err("Failed to decode commit CBOR: " # debug_show (e));
      };

      // Reconstruct repository state
      var allRecords = PureMap.empty<CID.CID, DagCbor.Value>();
      var allCommits = PureMap.empty<TID.TID, Commit>();
      var allBlobs = PureMap.empty<CID.CID, BlobRef.BlobRef>();

      // Reconstruct MST from the data CID in latest commit
      let mstHandler = switch (MSTHandler.fromBlockMap(latestCommitCID, blockMap)) {
        case (#err(e)) return #err("Failed to reconstruct MST: " # e);
        case (#ok(mstHandler)) mstHandler;
      };

      // Extract all records referenced by the MST
      switch (extractAllRecords(mstHandler, blockMap)) {
        case (#err(e)) return #err("Failed to extract records: " # e);
        case (#ok(records)) allRecords := records;
      };

      // Reconstruct commit history
      var currentCommitOpt : ?Commit.Commit = ?latestCommit;
      label w while (true) {
        switch (currentCommitOpt) {
          case (null) break w;
          case (?commit) {
            allCommits := PureMap.add(allCommits, TID.compare, commit.rev, commit);

            switch (commit.prev) {
              case (null) currentCommitOpt := null;
              case (?prevCID) {
                let ?prevData = PureMap.get(blockMap, compareCID, prevCID) else {
                  currentCommitOpt := null;
                  break w;
                };

                switch (DagCbor.fromBytes(prevData.vals())) {
                  case (#ok(prevValue)) {
                    switch (parseCommitFromCbor(prevValue)) {
                      case (#ok(prevCommit)) currentCommitOpt := ?prevCommit;
                      case (#err(_)) currentCommitOpt := null;
                    };
                  };
                  case (#err(_)) currentCommitOpt := null;
                };
              };
            };
          };
        };
      };

      // Create repository
      let newRepo : RepositoryWithData = {
        head = latestCommitCID;
        rev = latestCommit.rev;
        active = true;
        status = null;
        commits = allCommits;
        records = allRecords;
        nodes = mstHandler.getNodes();
        blobs = allBlobs;
      };

      // Check if repository already exists
      switch (PureMap.get(repositories, DIDModule.comparePlcDID, latestCommit.did)) {
        case (?_) return #err("Repository already exists for DID: " # DID.Plc.toText(latestCommit.did));
        case null ();
      };

      // Store the repository
      repositories := PureMap.add(repositories, DIDModule.comparePlcDID, latestCommit.did, newRepo);

      #ok(());
    };

    public func uploadBlob(request : UploadBlob.Request) : Result.Result<UploadBlob.Response, Text> {
      // Generate CID for the blob
      let blobCID = CIDBuilder.fromBlob(request.data);

      let blobWithMetaData : BlobWithMetaData = {
        data = request.data;
        mimeType = request.mimeType;
        createdAt = Time.now();
      };

      // TODO clear blob if it isn't referenced within a time window
      blobs := PureMap.add(
        stableData.blobs,
        compareCID,
        blobCID,
        blobWithMetaData,
      );

      #ok({
        blob = {
          ref = blobCID;
          mimeType = request.mimeType;
          size = Blob.size(request.data);
        };
      });
    };

    // Sync methods

    public func listBlobs(request : ListBlobs.Request) : Result.Result<ListBlobs.Response, Text> {
      let ?repo = PureMap.get(repositories, DIDModule.comparePlcDID, request.did) else return #err("Repository not found: " # DID.Plc.toText(request.did));

      // Get all blob CIDs from the repository
      let allBlobCIDs = PureMap.keys(repo.blobs) |> Iter.toArray(_);

      // TODO: Filter by 'since' parameter - would need to track which blobs were added in which commits
      // For now, returning all blobs regardless of 'since' parameter

      // Apply limit
      let limit = switch (request.limit) {
        case (?l) l;
        case (null) 500;
      };

      // Find start index based on cursor
      let startIndex = switch (request.cursor) {
        case (?cursor) {
          // Find the blob CID after the cursor
          var index = 0;
          label findCursor for (cid in allBlobCIDs.vals()) {
            let cidText = CID.toText(cid);
            if (cidText == cursor) {
              index += 1;
              break findCursor;
            };
            index += 1;
          };
          index;
        };
        case (null) 0;
      };

      // Get the slice of blob CIDs
      let endIndex = Nat.min(startIndex + limit, allBlobCIDs.size());
      let resultCIDs = if (startIndex >= allBlobCIDs.size()) {
        [];
      } else {
        Array.sliceToArray(allBlobCIDs, startIndex, endIndex);
      };

      // Generate next cursor
      let nextCursor = if (endIndex < allBlobCIDs.size()) {
        ?CID.toText(resultCIDs[resultCIDs.size() - 1]);
      } else {
        null;
      };

      #ok({
        cursor = nextCursor;
        cids = resultCIDs;
      });
    };

    // Stable data

    public func toStableData() : StableData {
      return {
        repositories = repositories;
        blobs = blobs;
      };
    };

    // Helper function to parse commit from CBOR value
    private func parseCommitFromCbor(value : DagCbor.Value) : Result.Result<Commit.Commit, Text> {
      switch (value) {
        case (#map(fields)) {
          var did : ?DID.Plc.DID = null;
          var version : ?Nat = null;
          var data : ?CID.CID = null;
          var rev : ?TID.TID = null;
          var prev : ?CID.CID = null;
          var sig : ?Blob = null;

          for ((key, val) in fields.vals()) {
            switch (key, val) {
              case ("did", #text(didText)) {
                switch (DID.Plc.fromText(didText)) {
                  case (#ok(d)) did := ?d;
                  case (#err(_)) return #err("Invalid DID in commit");
                };
              };
              case ("version", #int(v)) version := ?Int.abs(v);
              case ("data", #cid(cid)) {
                data := ?cid;
              };
              case ("rev", #text(revText)) {
                switch (TID.fromText(revText)) {
                  case (#ok(r)) rev := ?r;
                  case (#err(_)) return #err("Invalid rev in commit");
                };
              };
              case ("prev", #cid(cid)) {
                prev := ?cid;
              };
              case ("sig", #bytes(sigBytes)) sig := ?Blob.fromArray(sigBytes);
              case _ ();
            };
          };

          let ?d = did else return #err("Missing did in commit");
          let ?v = version else return #err("Missing version in commit");
          let ?dt = data else return #err("Missing data in commit");
          let ?r = rev else return #err("Missing rev in commit");
          let ?s = sig else return #err("Missing sig in commit");

          #ok({
            did = d;
            version = v;
            data = dt;
            prev = prev;
            rev = r;
            sig = s;
          });
        };
        case _ #err("Commit must be a CBOR map");
      };
    };

    // Helper function to extract all records from MST
    private func extractAllRecords(
      mstHandler : MSTHandler.Handler,
      blockMap : PureMap.Map<CID.CID, Blob>,
    ) : Result.Result<PureMap.Map<CID.CID, DagCbor.Value>, Text> {
      var records = PureMap.empty<CID.CID, DagCbor.Value>();

      // Get all CID references from MST
      let allCIDs = mstHandler.getAllRecordCIDs();

      for (cid in allCIDs.vals()) {
        let ?blockData = PureMap.get(blockMap, compareCID, cid) else {
          return #err("Record block not found: " # CID.toText(cid));
        };

        switch (DagCbor.fromBytes(blockData.vals())) {
          case (#ok(value)) {
            records := PureMap.add(records, compareCID, cid, value);
          };
          case (#err(e)) {
            return #err("Failed to decode record: " # debug_show (e));
          };
        };
      };

      #ok(records);
    };

    private func createCommit(
      repoId : DID.Plc.DID,
      rev : TID.TID,
      newNodeCID : CID.CID,
      lastNodeCID : ?CID.CID,
    ) : async* Result.Result<Commit.Commit, Text> {

      let unsignedCommit : Commit.UnsignedCommit = {
        did = repoId;
        version = 3; // TODO?
        data = newNodeCID;
        rev = rev;
        prev = lastNodeCID;
      };

      // Sign commit
      switch (await* signCommit(unsignedCommit)) {
        case (#ok(commit)) #ok(commit);
        case (#err(e)) return #err("Failed to sign commit: " # e);
      };
    };

    private func signCommit(unsigned : Commit.UnsignedCommit) : async* Result.Result<Commit.Commit, Text> {
      // Serialize unsigned commit to CBOR
      let cid = CIDBuilder.fromUnsignedCommit(unsigned);
      let hash = CID.getHash(cid);

      // Sign with rotation key
      let signature = switch (await* keyHandler.sign(#rotation, hash)) {
        case (#ok(sig)) sig;
        case (#err(e)) return #err(e);
      };

      #ok({
        unsigned with
        sig = signature;
      });
    };

    func compareCID(cid1 : CID.CID, cid2 : CID.CID) : Order.Order {
      // TODO is this the right way to compare CIDs?
      if (cid1 == cid2) return #equal;

      let hash1 = CID.getHash(cid1);
      let hash2 = CID.getHash(cid2);
      Blob.compare(hash1, hash2);
    };
  };
};
