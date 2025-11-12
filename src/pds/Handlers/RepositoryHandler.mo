import Repository "../../atproto/Repository";
import ServerInfoHandler "./ServerInfoHandler";
import CID "mo:cid@1";
import TID "mo:tid@1";
import PureMap "mo:core@1/pure/Map";
import DagCbor "mo:dag-cbor@2";
import CIDBuilder "../../atproto/CIDBuilder";
import Result "mo:core@1/Result";
import KeyHandler "../Handlers/KeyHandler";
import Text "mo:core@1/Text";
import Blob "mo:core@1/Blob";
import Iter "mo:core@1/Iter";
import LexiconValidator "../../atproto/LexiconValidator";
import Nat "mo:core@1/Nat";
import Array "mo:core@1/Array";
import Time "mo:core@1/Time";
import List "mo:core@1/List";
import Runtime "mo:core@1/Runtime";
import BlobRef "../../atproto/BlobRef";
import RepositoryMessageHandler "./RepositoryMessageHandler";
import Car "mo:car@1";
import CarUtil "../CarUtil";

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

  public type OnCommitCallback = (RepositoryMessageHandler.Commit) -> ();

  public class Handler(
    stableData : ?StableData,
    keyHandler : KeyHandler.HandlerInterface,
    serverInfoHandler : ServerInfoHandler.Handler,
    tidGenerator : TID.Generator,
    onCommit : OnCommitCallback,
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
          let did = serverInfoHandler.get().plcIdentifier;
          let rev = tidGenerator.next();
          let signFunc = getSignFunc();
          let repository = switch (await* Repository.empty(did, rev, signFunc)) {
            case (#ok(repo)) repo;
            case (#err(e)) return #err("Failed to create new repository: " # e);
          };

          let newBlocks = switch (CarUtil.fromRepository(repository, #full({ includeHistorical = false }))) {
            case (#ok(data)) data;
            case (#err(e)) Runtime.trap("Failed to export repository data for event: " # e);
          };
          let newBlocksBlob = Blob.fromArray(Car.toBytes(newBlocks));

          onCommit({
            repo = did;
            commit = repository.head;
            rev = rev;
            blocks = newBlocksBlob;
            ops = [];
            prevData = null;
          });
          repository;
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
      Repository.collectionKeys(repository) |> Iter.toArray(_);
    };

    public func getRecord(request : GetRecordRequest) : ?GetRecordResponse {
      let repository = getRepository();

      let ?recordData = Repository.getRecord(
        repository,
        {
          collection = request.collection;
          recordKey = request.rkey;
        },
      ) else return null;
      ?{
        cid = recordData.cid;
        value = recordData.value;
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
      let key = {
        collection = request.collection;
        recordKey = rKey;
      };
      let did = serverInfoHandler.get().plcIdentifier;
      let rev = tidGenerator.next();
      let signFunc = getSignFunc();
      let (newRepository, recordCID) = switch (
        await* Repository.createRecord(
          repository,
          key,
          request.record,
          did,
          rev,
          signFunc,
        )
      ) {
        case (#ok(repo, cid)) (repo, cid);
        case (#err(e)) return #err("Failed to create record: " # e);
      };

      setRepository(newRepository);

      // Emit message via callback
      let newBlocks = switch (CarUtil.fromRepository(newRepository, #since(repository.rev))) {
        case (#ok(data)) data;
        case (#err(e)) Runtime.trap("Failed to export repository data for event: " # e);
      };
      let newBlocksBlob = Blob.fromArray(Car.toBytes(newBlocks));

      let prevData = Repository.getMstRootCid(repository);

      onCommit({
        repo = did;
        commit = newRepository.head;
        rev = rev;
        blocks = newBlocksBlob;
        ops = [{
          action = #create({ cid = recordCID });
          key = key;
        }];
        prevData = ?prevData;
      });

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

      switch (validateSwapRecord(repository, request.collection, request.rkey, request.swapRecord)) {
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

      let did = serverInfoHandler.get().plcIdentifier;
      let rev = tidGenerator.next();
      let signFunc = getSignFunc();
      let (newRepository, { newCid = newRecordCid; prevCid = prevRecordCid }) = switch (
        await* Repository.putRecord(
          repository,
          {
            collection = request.collection;
            recordKey = request.rkey;
          },
          request.record,
          did,
          rev,
          signFunc,
        )
      ) {
        case (#ok(repo, cid)) (repo, cid);
        case (#err(e)) return #err("Failed to put record: " # e);
      };
      setRepository(newRepository);

      // Emit event via callback
      let blocks = switch (CarUtil.fromRepository(newRepository, #since(repository.rev))) {
        case (#ok(data)) data;
        case (#err(e)) Runtime.trap("Failed to export repository data for event: " # e);
      };

      let newBlocksBlob = Blob.fromArray(Car.toBytes(blocks));

      let prevData = Repository.getMstRootCid(repository);
      onCommit({
        repo = did;
        commit = newRepository.head;
        rev = rev;
        blocks = newBlocksBlob;
        ops = [{
          action = #update({ newCid = newRecordCid; prevCid = prevRecordCid });
          key = {
            collection = request.collection;
            recordKey = request.rkey;
          };
        }];
        prevData = ?prevData;
      });

      #ok({
        cid = newRecordCid;
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

      switch (validateSwapRecord(repository, request.collection, request.rkey, request.swapRecord)) {
        case (#ok(())) ();
        case (#err(e)) return #err(e);
      };

      let did = serverInfoHandler.get().plcIdentifier;
      let rev = tidGenerator.next();
      let signFunc = getSignFunc();
      let (newRepository, deletedRecordCID) = switch (
        await* Repository.deleteRecord(
          repository,
          {
            collection = request.collection;
            recordKey = request.rkey;
          },
          did,
          rev,
          signFunc,
        )
      ) {
        case (#ok(repo, cid)) (repo, cid);
        case (#err(e)) return #err("Failed to delete record: " # e);
      };
      setRepository(newRepository);

      // Emit event via callback

      let blocks = switch (CarUtil.fromRepository(newRepository, #since(repository.rev))) {
        case (#ok(data)) data;
        case (#err(e)) Runtime.trap("Failed to export repository data for event: " # e);
      };
      let newBlocksBlob = Blob.fromArray(Car.toBytes(blocks));

      let prevData = Repository.getMstRootCid(repository);
      onCommit({
        repo = did;
        commit = newRepository.head;
        rev = rev;
        blocks = newBlocksBlob;
        ops = [{
          action = #delete({ cid = deletedRecordCID });
          key = {
            collection = request.collection;
            recordKey = request.rkey;
          };
        }];
        prevData = ?prevData;
      });

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

      let writeOperations = List.empty<Repository.WriteOperation>();
      let validationStatuses = List.empty<ValidationStatus>();
      for (writeOp in request.writes.vals()) {
        switch (buildWriteOperation(writeOp, request.validate)) {
          case (#ok((op, validationStatus))) {
            List.add(writeOperations, op);
            List.add(validationStatuses, validationStatus);
          };
          case (#err(e)) return #err(e);
        };
      };
      let did = serverInfoHandler.get().plcIdentifier;
      let rev = tidGenerator.next();
      let signFunc = getSignFunc();
      let (newRepository, results) = switch (
        await* Repository.applyWrites(
          repository,
          List.toArray(writeOperations),
          did,
          rev,
          signFunc,
        )
      ) {
        case (#ok(repo, res)) (repo, res);
        case (#err(e)) return #err("Failed to apply writes: " # e);
      };

      setRepository(newRepository);

      // Emit events via callback for each write operation
      let operations : [RepositoryMessageHandler.Operation] = results.vals()
      |> Iter.map(
        _,
        func(writeResult : Repository.WriteResult) : RepositoryMessageHandler.Operation {
          switch (writeResult) {
            case (#create(createRes)) {
              {
                action = #create({ cid = createRes.cid });
                key = createRes.key;
              };
            };
            case (#update(updateRes)) {
              {
                action = #update({
                  newCid = updateRes.newCid;
                  prevCid = updateRes.prevCid;
                });
                key = updateRes.key;
              };
            };
            case (#delete(deleteRes)) {
              {
                action = #delete({ cid = deleteRes.cid });
                key = deleteRes.key;
              };
            };
          };
        },
      )
      |> Iter.toArray(_);

      let newBlocks = switch (CarUtil.fromRepository(newRepository, #since(repository.rev))) {
        case (#ok(data)) data;
        case (#err(e)) Runtime.trap("Failed to export repository data for event: " # e);
      };
      let newBlocksBlob = Blob.fromArray(Car.toBytes(newBlocks));

      let prevData = Repository.getMstRootCid(repository);

      onCommit({
        repo = did;
        commit = newRepository.head;
        rev = rev;
        blocks = newBlocksBlob;
        ops = operations;
        prevData = ?prevData;
      });

      #ok({
        commit = ?{
          cid = newRepository.head;
          rev = newRepository.rev;
        };
        results = results.vals()
        |> Iter.zipWith<Repository.WriteResult, ValidationStatus, WriteResult>(
          _,
          List.values(validationStatuses),
          func(writeResult : Repository.WriteResult, validationStatus : ValidationStatus) : WriteResult {
            switch (writeResult) {
              case (#create(createRes)) #create({
                collection = createRes.key.collection;
                rkey = createRes.key.recordKey;
                cid = createRes.cid;
                validationStatus = validationStatus;
              });
              case (#update(updateRes)) #update({
                collection = updateRes.key.collection;
                rkey = updateRes.key.recordKey;
                cid = updateRes.newCid;
                validationStatus = validationStatus;
              });
              case (#delete(_)) #delete({});
            };
          },
        )
        |> Iter.toArray(_);
      });
    };

    private func buildWriteOperation(
      writeOp : WriteOperation,
      validate : ?Bool,
    ) : Result.Result<(Repository.WriteOperation, ValidationStatus), Text> {
      switch (writeOp) {
        case (#create(createOp)) {
          let rKey : Text = switch (createOp.rkey) {
            case (?rkey) rkey;
            case (null) TID.toText(tidGenerator.next());
          };

          // Validate record
          let validationResult : Result.Result<ValidationStatus, Text> = switch (validate) {
            case (?true) LexiconValidator.validateRecord(createOp.value, createOp.collection, false);
            case (?false) #ok(#unknown);
            case (null) LexiconValidator.validateRecord(createOp.value, createOp.collection, true);
          };
          let validationStatus = switch (validationResult) {
            case (#ok(status)) status;
            case (#err(e)) return #err("Record validation failed: " # e);
          };

          let operation = #create({
            key = {
              collection = createOp.collection;
              recordKey = rKey;
            };
            value = createOp.value;
          });
          #ok((operation, validationStatus));
        };
        case (#update(updateOp)) {
          // Validate record
          let validationResult : Result.Result<ValidationStatus, Text> = switch (validate) {
            case (?true) LexiconValidator.validateRecord(updateOp.value, updateOp.collection, false);
            case (?false) #ok(#unknown);
            case (null) LexiconValidator.validateRecord(updateOp.value, updateOp.collection, true);
          };
          let validationStatus = switch (validationResult) {
            case (#ok(status)) status;
            case (#err(e)) return #err("Record validation failed: " # e);
          };

          let operation = #update({
            key = {
              collection = updateOp.collection;
              recordKey = updateOp.rkey;
            };
            value = updateOp.value;
          });
          #ok((operation, validationStatus));
        };
        case (#delete(deleteOp)) {
          let operation = #delete({
            key = {
              collection = deleteOp.collection;
              recordKey = deleteOp.rkey;
            };
          });
          #ok((operation, #unknown));
        };
      };
    };

    public func listRecords(request : ListRecordsRequest) : ListRecordsResponse {
      let repository = getRepository();

      // TODO optimize for reverse/limit/cursor
      let records = Repository.recordEntriesByCollection(repository, request.collection);

      // Apply reverse ordering if requested
      let orderedRecords = switch (request.reverse) {
        case (?true) Iter.toArray(Iter.reverse(records));
        case (_) Iter.toArray(records);
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
          label findCursor for ((key, data) in orderedRecords.vals()) {
            let recordUri = Repository.keyToText(key);
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
        orderedRecords.vals()
        |> Iter.drop(_, startIndex)
        |> Iter.take(_, (endIndex - startIndex : Nat))
        |> Iter.map(
          _,
          func((key, data) : (Repository.Key, Repository.RecordData)) : ListRecord {
            {
              collection = key.collection;
              rkey = key.recordKey;
              cid = data.cid;
              value = data.value;
            };
          },
        ) |> Iter.toArray(_);
      };

      // Generate next cursor
      let nextCursor = if (endIndex < orderedRecords.size()) {
        let lastRecord = resultRecords[resultRecords.size() - 1];
        ?Repository.keyToText({
          collection = lastRecord.collection;
          recordKey = lastRecord.rkey;
        });
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

    private func getSignFunc() : (Blob) -> async* Result.Result<Blob, Text> {
      func(data : Blob) : async* Result.Result<Blob, Text> {
        await* keyHandler.sign(#verification, data);
      };
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
      repository : Repository.Repository,
      collection : Text,
      rkey : Text,
      swapRecord : ?CID.CID,
    ) : Result.Result<(), Text> {
      // Validate swapRecord if provided
      switch (swapRecord) {
        case (?expectedRecordCID) {
          // Check if record currently exists and matches expected CID
          let key = {
            collection = collection;
            recordKey = rkey;
          };
          let ?recordData = Repository.getRecord(repository, key) else return #err("Swap record failed: expected record " # CID.toText(expectedRecordCID) # " but record does not exist");
          // Record exists, check if it matches expected CID
          if (recordData.cid != expectedRecordCID) {
            return #err("Swap record failed: expected " # CID.toText(expectedRecordCID) # " but current record is " # CID.toText(recordData.cid));
          };
        };
        case (null) ();
      };
      #ok;
    };

  };

};
