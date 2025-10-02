import Repository "../../atproto/Repository";
import ServerInfoHandler "./ServerInfoHandler";
import DID "mo:did@3";
import CID "mo:cid@1";
import TID "mo:tid@1";
import PureMap "mo:core@1/pure/Map";
import Commit "../../atproto/Commit";
import DagCbor "mo:dag-cbor@2";
import CIDBuilder "../../atproto/CIDBuilder";
import AtUri "../../atproto/AtUri";
import Result "mo:core@1/Result";
import KeyHandler "../Handlers/KeyHandler";
import Text "mo:core@1/Text";
import Order "mo:core@1/Order";
import Blob "mo:core@1/Blob";
import MerkleSearchTree "../../atproto/MerkleSearchTree";
import MerkleNode "../../atproto/MerkleNode";
import Iter "mo:core@1/Iter";
import LexiconValidator "../../atproto/LexiconValidator";
import Debug "mo:core@1/Debug";
import Domain "mo:url-kit@3/Domain";
import DIDModule "../DID";
import Nat "mo:core@1/Nat";
import Array "mo:core@1/Array";
import Time "mo:core@1/Time";
import List "mo:core@1/List";
import Runtime "mo:core@1/Runtime";
import Int "mo:core@1/Int";
import Set "mo:core@1/Set";
import BlobRef "../../atproto/BlobRef";

module {
  public type StableData = {
    repository : Repository.Repository;
    blobs : PureMap.Map<CID.CID, BlobWithMetaData>;
  };

  public type BlobWithMetaData = {
    data : Blob;
    mimeType : Text;
    createdAt : Time.Time;
  };

  public type CreateRecordRequest = {
    collection : Text;
    rkey : ?Text;
    record : DagCbor.Value;
    validate : ?Bool;
    swapCommit : ?CID.CID;
  };

  public type CreateRecordResponse = {
    rkey : Text;
    cid : CID.CID;
    commit : ?CommitMeta;
    validationStatus : ValidationStatus;
  };

  public type CommitMeta = {
    cid : CID.CID;
    rev : TID.TID;
  };

  public type ValidationStatus = {
    #valid;
    #unknown;
  };

  public type GetRecordRequest = {
    collection : Text;
    rkey : Text;
    cid : ?CID.CID;
  };

  public type GetRecordResponse = {
    cid : CID.CID;
    value : DagCbor.Value;
  };

  public type PutRecordRequest = {
    collection : Text;
    rkey : Text;
    record : DagCbor.Value;
    validate : ?Bool;
    swapCommit : ?CID.CID;
    swapRecord : ?CID.CID;
  };

  public type PutRecordResponse = {
    cid : CID.CID;
    commit : ?CommitMeta;
    validationStatus : ?ValidationStatus;
  };

  public type DeleteRecordRequest = {
    collection : Text;
    rkey : Text;
    swapCommit : ?CID.CID;
    swapRecord : ?CID.CID;
  };

  public type DeleteRecordResponse = {
    commit : ?CommitMeta;
  };

  public type ApplyWritesRequest = {
    validate : ?Bool;
    writes : [WriteOperation];
    swapCommit : ?CID.CID;
  };

  public type WriteOperation = {
    #create : CreateOp;
    #update : UpdateOp;
    #delete : DeleteOp;
  };

  public type CreateOp = {
    collection : Text;
    rkey : ?Text;
    value : DagCbor.Value;
  };

  public type UpdateOp = {
    collection : Text;
    rkey : Text;
    value : DagCbor.Value;
  };

  public type DeleteOp = {
    collection : Text;
    rkey : Text;
  };

  public type ApplyWritesResponse = {
    commit : ?CommitMeta;
    results : [WriteResult];
  };

  public type WriteResult = {
    #create : CreateResult;
    #update : UpdateResult;
    #delete : DeleteResult;
  };

  public type CreateResult = {
    collection : Text;
    rkey : Text;
    cid : CID.CID;
    validationStatus : ValidationStatus;
  };

  public type UpdateResult = {
    collection : Text;
    rkey : Text;
    cid : CID.CID;
    validationStatus : ValidationStatus;
  };

  public type DeleteResult = {};

  public type ListRecordsRequest = {
    collection : Text;
    limit : ?Nat;
    cursor : ?Text;
    rkeyStart : ?Text;
    rkeyEnd : ?Text;
    reverse : ?Bool;
  };

  public type ListRecordsResponse = {
    cursor : ?Text;
    records : [ListRecord];
  };

  public type ListRecord = {
    collection : Text;
    rkey : Text;
    cid : CID.CID;
    value : DagCbor.Value;
  };

  public type ImportRepoRequest = {
    header : {
      roots : [CID.CID];
      version : Nat;
    };
    blocks : [{
      cid : CID.CID;
      data : Blob;
    }];
  };

  public type UploadBlobRequest = {
    data : Blob;
    mimeType : Text;
  };

  public type UploadBlobResponse = {
    blob : BlobRef.BlobRef;
  };

  public type ListBlobsRequest = {
    limit : ?Nat;
    cursor : ?Text;
    since : ?TID.TID;
  };

  public type ListBlobsResponse = {
    cursor : ?Text;
    cids : [CID.CID];
  };

  public class Handler(
    stableData : ?StableData,
    keyHandler : KeyHandler.Handler,
    serverInfoHandler : ServerInfoHandler.Handler,
    tidGenerator : TID.Generator,
  ) {
    var dataOrNull = stableData;

    public func get() : Repository.Repository {
      getRepository();
    };

    private func getDataOrTrap() : StableData {
      let ?data = dataOrNull else Runtime.trap("Repository not initialized");
      data;
    };

    private func getRepository() : Repository.Repository {
      let ?data = dataOrNull else Runtime.trap("Repository not initialized");
      data.repository;
    };

    private func setRepository(repository : Repository.Repository) : () {
      let data = getDataOrTrap();
      dataOrNull := ?{
        data with
        repository = repository;
      };
    };

    public func initialize(existingRepository : ?Repository.Repository) : async* Result.Result<(), Text> {
      if (dataOrNull != null) {
        return #err("Repository already initialized");
      };

      let repository : Repository.Repository = switch (existingRepository) {
        case (?repository) repository;
        case (null) {
          let mst = MerkleSearchTree.empty();
          let rev = tidGenerator.next();
          let signedCommit = switch (await* createCommit(rev, mst.root, null)) {
            case (#ok(commit)) commit;
            case (#err(e)) return #err("Failed to create commit: " # e);
          };
          let signedCommitCID = CIDBuilder.fromCommit(signedCommit);
          {
            head = signedCommitCID;
            rev = rev;
            active = true;
            status = null;
            commits = PureMap.singleton<TID.TID, Commit.Commit>(rev, signedCommit);
            records = PureMap.empty<CID.CID, DagCbor.Value>();
            nodes = mst.nodes;
            blobs = PureMap.empty<CID.CID, BlobRef.BlobRef>();
          };
        };
      };

      dataOrNull := ?{
        repository = repository;
        blobs = PureMap.empty<CID.CID, BlobWithMetaData>();
      };

      #ok;
    };

    public func getAllCollections() : [Text] {
      let repository = getRepository();
      let mst = Repository.buildMerkleSearchTree(repository);
      let collections = Set.empty<Text>();
      for ((key, _) in MerkleSearchTree.entries(mst)) {
        let parts = Iter.toArray(Text.split(key, #char('/')));
        // TODO how to handle invalid keys here? if size is < 2?
        if (parts.size() >= 2) {
          Set.add(collections, Text.compare, parts[0]);
        };
      };
      Iter.toArray(Set.values(collections));
    };

    public func getRecord(request : GetRecordRequest) : ?GetRecordResponse {
      let path = request.collection # "/" # request.rkey;
      let repository = getRepository();

      let mst = Repository.buildMerkleSearchTree(repository);

      let ?recordCID = MerkleSearchTree.get(mst, path) else return null;
      let ?value = PureMap.get(repository.records, CIDBuilder.compare, recordCID) else return null;
      ?{
        cid = recordCID;
        value = value;
      };
    };

    public func createRecord(
      request : CreateRecordRequest
    ) : async* Result.Result<CreateRecordResponse, Text> {

      let repository = getRepository();
      let rKey : Text = switch (request.rkey) {
        case (?rkey) {
          if (Text.size(rkey) > 512) {
            return #err("Record key exceeds maximum length of 512 characters");
          };
          rkey;
        };
        case (null) TID.toText(tidGenerator.next());
      };

      switch (validateSwapCommit(repository, request.swapCommit)) {
        case (#ok(())) ();
        case (#err(e)) return #err(e);
      };

      let validationResult : Result.Result<ValidationStatus, Text> = switch (request.validate) {
        case (?true) LexiconValidator.validateRecord(request.record, request.collection, false);
        case (?false) #ok(#unknown);
        case (null) LexiconValidator.validateRecord(request.record, request.collection, true);
      };
      let validationStatus = switch (validationResult) {
        case (#ok(status)) status;
        case (#err(e)) return #err("Record validation failed: " # e);
      };

      let recordCID = CIDBuilder.fromRecord(rKey, request.record);

      // Create record path
      let path = request.collection # "/" # rKey;

      let mst = Repository.buildMerkleSearchTree(repository);

      // Add to MST
      let newMst = switch (MerkleSearchTree.add(mst, path, recordCID)) {
        case (#ok(mst)) mst;
        case (#err(e)) return #err("Failed to add to MST: " # debug_show (e));
      };

      let newRecords = PureMap.add(
        repository.records,
        CIDBuilder.compare,
        recordCID,
        request.record,
      );

      let newRepository = switch (
        await* commitNewData(
          repository,
          mst,
          newMst,
          newRecords,
        )
      ) {
        case (#ok(repo)) repo;
        case (#err(e)) return #err(e);
      };

      #ok({
        cid = recordCID;
        commit = ?{
          cid = newRepository.head;
          rev = newRepository.rev;
        };
        rkey = rKey;
        validationStatus = validationStatus;
      });
    };

    public func putRecord(request : PutRecordRequest) : async* Result.Result<PutRecordResponse, Text> {

      let repository = getRepository();

      switch (validateSwapCommit(repository, request.swapCommit)) {
        case (#ok(())) ();
        case (#err(e)) return #err(e);
      };

      let mst = Repository.buildMerkleSearchTree(repository);

      switch (validateSwapRecord(mst, request.collection, request.rkey, request.swapRecord)) {
        case (#ok(())) ();
        case (#err(e)) return #err(e);
      };

      let validationResult : Result.Result<ValidationStatus, Text> = switch (request.validate) {
        case (?true) LexiconValidator.validateRecord(request.record, request.collection, false);
        case (?false) #ok(#unknown);
        case (null) LexiconValidator.validateRecord(request.record, request.collection, true);
      };
      let validationStatus = switch (validationResult) {
        case (#ok(status)) status;
        case (#err(e)) return #err("Record validation failed: " # e);
      };

      let recordCID = CIDBuilder.fromRecord(request.rkey, request.record);

      // Create record path
      let path = request.collection # "/" # request.rkey;

      // Update MST (this will replace existing record)
      let newMst = switch (MerkleSearchTree.add(mst, path, recordCID)) {
        case (#ok(mst)) mst;
        case (#err(e)) return #err("Failed to update MST: " # debug_show (e));
      };

      let newRecords = PureMap.add(
        repository.records,
        CIDBuilder.compare,
        recordCID,
        request.record,
      );

      let newRepository = switch (
        await* commitNewData(
          repository,
          mst,
          newMst,
          newRecords,
        )
      ) {
        case (#ok(repo)) repo;
        case (#err(e)) return #err(e);
      };

      #ok({
        cid = recordCID;
        commit = ?{
          cid = newRepository.head;
          rev = newRepository.rev;
        };
        validationStatus = ?validationStatus;
      });
    };

    public func deleteRecord(request : DeleteRecordRequest) : async* Result.Result<DeleteRecordResponse, Text> {

      let repository = getRepository();

      switch (validateSwapCommit(repository, request.swapCommit)) {
        case (#ok(())) ();
        case (#err(e)) return #err(e);
      };

      let mst = Repository.buildMerkleSearchTree(repository);

      switch (validateSwapRecord(mst, request.collection, request.rkey, request.swapRecord)) {
        case (#ok(())) ();
        case (#err(e)) return #err(e);
      };

      let path = request.collection # "/" # request.rkey;

      // Remove from MST
      let (newMst, removedValue) = switch (MerkleSearchTree.remove(mst, path)) {
        case (#ok(mst)) mst;
        case (#err(e)) return #err("Failed to remove from MST: " # debug_show (e));
      };

      let newRecords = PureMap.remove(
        repository.records,
        CIDBuilder.compare,
        removedValue,
      );

      let newRepository = switch (
        await* commitNewData(
          repository,
          mst,
          newMst,
          newRecords,
        )
      ) {
        case (#ok(repo)) repo;
        case (#err(e)) return #err(e);
      };

      #ok({
        commit = ?{
          cid = newRepository.head;
          rev = newRepository.rev;
        };
      });
    };

    public func applyWrites(request : ApplyWritesRequest) : async* Result.Result<ApplyWritesResponse, Text> {
      let repository = getRepository();

      switch (validateSwapCommit(repository, request.swapCommit)) {
        case (#ok(())) ();
        case (#err(e)) return #err(e);
      };

      var updatedRecords = repository.records;
      let mst = Repository.buildMerkleSearchTree(repository);
      var newMst = mst;

      // Process all write operations and collect results
      let results = List.empty<WriteResult>();

      for (writeOp in request.writes.vals()) {
        let result : WriteResult = switch (writeOp) {
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
            let validationResult : Result.Result<ValidationStatus, Text> = switch (request.validate) {
              case (?true) LexiconValidator.validateRecord(createOp.value, createOp.collection, false);
              case (?false) #ok(#unknown);
              case (null) LexiconValidator.validateRecord(createOp.value, createOp.collection, true);
            };
            let validationStatus = switch (validationResult) {
              case (#ok(status)) status;
              case (#err(e)) return #err("Record validation failed: " # e);
            };

            let recordCID = CIDBuilder.fromRecord(rKey, createOp.value);
            updatedRecords := PureMap.add(updatedRecords, CIDBuilder.compare, recordCID, createOp.value);

            // Create record path for MST
            let path = createOp.collection # "/" # rKey;

            // Add to MST
            newMst := switch (MerkleSearchTree.add(newMst, path, recordCID)) {
              case (#ok(mst)) mst;
              case (#err(e)) return #err("Failed to add to MST: " # debug_show (e));
            };

            #create({
              collection = createOp.collection;
              rkey = rKey;
              cid = recordCID;
              validationStatus = validationStatus;
            });
          };
          case (#update(updateOp)) {
            if (Text.size(updateOp.rkey) > 512) {
              return #err("Record key exceeds maximum length of 512 characters");
            };

            // Validate record
            let validationResult : Result.Result<ValidationStatus, Text> = switch (request.validate) {
              case (?true) LexiconValidator.validateRecord(updateOp.value, updateOp.collection, false);
              case (?false) #ok(#unknown);
              case (null) LexiconValidator.validateRecord(updateOp.value, updateOp.collection, true);
            };
            let validationStatus = switch (validationResult) {
              case (#ok(status)) status;
              case (#err(e)) return #err("Record validation failed: " # e);
            };

            let recordCID = CIDBuilder.fromRecord(updateOp.rkey, updateOp.value);
            updatedRecords := PureMap.add(updatedRecords, CIDBuilder.compare, recordCID, updateOp.value);

            // Create record path for MST
            let path = updateOp.collection # "/" # updateOp.rkey;
            // Update MST (this will replace existing record)
            newMst := switch (MerkleSearchTree.add(newMst, path, recordCID)) {
              case (#ok(mst)) mst;
              case (#err(e)) return #err("Failed to update MST: " # debug_show (e));
            };

            #update({
              collection = updateOp.collection;
              rkey = updateOp.rkey;
              cid = recordCID;
              validationStatus = validationStatus;
            });
          };
          case (#delete(deleteOp)) {
            // Create record path for MST
            let path = deleteOp.collection # "/" # deleteOp.rkey;

            // Remove from MST
            newMst := switch (MerkleSearchTree.remove(newMst, path)) {
              case (#ok((mst, _))) mst;
              case (#err(e)) return #err("Failed to remove from MST: " # debug_show (e));
            };

            #delete({});
          };
        };
        List.add(results, result);
      };

      let newRepository = switch (
        await* commitNewData(
          repository,
          mst,
          newMst,
          updatedRecords,
        )
      ) {
        case (#ok(repo)) repo;
        case (#err(e)) return #err(e);
      };

      #ok({
        commit = ?{
          cid = newRepository.head;
          rev = newRepository.rev;
        };
        results = List.toArray(results);
      });
    };

    public func listRecords(request : ListRecordsRequest) : ListRecordsResponse {
      let repository = getRepository();
      let mst = Repository.buildMerkleSearchTree(repository);

      // TODO optimize for reverse/limit/cursor
      let collectionPrefix = request.collection # "/";
      // Convert to ListRecord format
      let records = MerkleSearchTree.entries(mst)
      |> Iter.filterMap<(key : Text, CID.CID), ListRecord>(
        _,
        func((key, cid) : (key : Text, CID.CID)) : ?ListRecord {
          let ?value : ?DagCbor.Value = PureMap.get(repository.records, CIDBuilder.compare, cid) else Runtime.trap("Record not found: " # CID.toText(cid));
          // Check if collection matches
          let ?rkey = Text.stripStart(key, #text(collectionPrefix)) else return null;

          ?{
            collection = request.collection;
            rkey = rkey;
            cid = cid;
            value = value;
          };
        },
      )
      |> Iter.toArray(_);

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
            let recordUri = record.collection # "/" # record.rkey;
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
        let lastRecord = resultRecords[resultRecords.size() - 1];
        ?(lastRecord.collection # "/" # lastRecord.rkey);
      } else {
        null;
      };

      {
        cursor = nextCursor;
        records = resultRecords;
      };
    };

    public func uploadBlob(request : UploadBlobRequest) : Result.Result<UploadBlobResponse, Text> {
      // Generate CID for the blob
      let blobCID = CIDBuilder.fromBlob(request.data);

      let blobWithMetaData : BlobWithMetaData = {
        data = request.data;
        mimeType = request.mimeType;
        createdAt = Time.now();
      };

      // TODO clear blob if it isn't referenced within a time window
      let data = getDataOrTrap();

      dataOrNull := ?{
        data with
        blobs = PureMap.add(
          data.blobs,
          CIDBuilder.compare,
          blobCID,
          blobWithMetaData,
        );
      };

      #ok({
        blob = {
          ref = blobCID;
          mimeType = request.mimeType;
          size = Blob.size(request.data);
        };
      });
    };

    // Sync methods

    public func listBlobs(request : ListBlobsRequest) : Result.Result<ListBlobsResponse, Text> {
      let repository = getRepository();
      // Get all blob CIDs from the repository
      let allBlobCIDs = PureMap.keys(repository.blobs) |> Iter.toArray(_);

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

    public func toStableData() : ?StableData {
      dataOrNull;
    };

    private func validateSwapCommit(
      repository : Repository.Repository,
      swapCommit : ?CID.CID,
    ) : Result.Result<(), Text> {
      // Validate swapCommit if provided
      switch (swapCommit) {
        case (?expectedCommitCID) {
          // Check that the current head commit matches the expected CID
          if (repository.head != expectedCommitCID) {
            return #err("Swap commit failed: expected " # CID.toText(expectedCommitCID) # " but current head is " # CID.toText(repository.head));
          };
        };
        case (null) ();
      };
      #ok;
    };

    private func validateSwapRecord(
      mst : MerkleSearchTree.MerkleSearchTree,
      collection : Text,
      rkey : Text,
      swapRecord : ?CID.CID,
    ) : Result.Result<(), Text> {
      // Validate swapRecord if provided
      switch (swapRecord) {
        case (?expectedRecordCID) {
          // Check if record currently exists and matches expected CID
          let path = collection # "/" # rkey;
          let ?currentRecordCID = MerkleSearchTree.get(mst, path) else return #err("Swap record failed: expected record " # CID.toText(expectedRecordCID) # " but record does not exist");
          // Record exists, check if it matches expected CID
          if (currentRecordCID != expectedRecordCID) {
            return #err("Swap record failed: expected " # CID.toText(expectedRecordCID) # " but current record is " # CID.toText(currentRecordCID));
          };
        };
        case (null) ();
      };
      #ok;
    };

    private func commitNewData(
      repository : Repository.Repository,
      mst : MerkleSearchTree.MerkleSearchTree,
      newMst : MerkleSearchTree.MerkleSearchTree,
      newRecords : PureMap.Map<CID.CID, DagCbor.Value>,
    ) : async* Result.Result<Repository.Repository, Text> {

      // Create new commit
      let newRev = tidGenerator.next();

      let signedCommit = switch (
        await* createCommit(
          newRev,
          newMst.root,
          ?mst.root,
        )
      ) {
        case (#ok(commit)) commit;
        case (#err(e)) return #err("Failed to create commit: " # e);
      };

      // Store new state
      let commitCID = CIDBuilder.fromCommit(signedCommit);
      let updatedCommits = PureMap.add<TID.TID, Commit.Commit>(
        repository.commits,
        TID.compare,
        newRev,
        signedCommit,
      );

      let newRepository : Repository.Repository = {
        repository with
        head = commitCID;
        rev = newRev;
        commits = updatedCommits;
        nodes = newMst.nodes;
        records = newRecords;
      };
      setRepository(newRepository);
      #ok(newRepository);
    };
    private func createCommit(
      rev : TID.TID,
      newNodeCID : CID.CID,
      lastNodeCID : ?CID.CID,
    ) : async* Result.Result<Commit.Commit, Text> {
      let serverInfo = serverInfoHandler.get();

      let unsignedCommit : Commit.UnsignedCommit = {
        did = serverInfo.plcIdentifier;
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

    private func signCommit(
      unsigned : Commit.UnsignedCommit
    ) : async* Result.Result<Commit.Commit, Text> {
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

  };

};
