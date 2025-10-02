import DID "mo:did@3";
import CID "mo:cid@1";
import TID "mo:tid@1";
import DagCbor "mo:dag-cbor@2";
import AtUri "./AtUri";
import PureMap "mo:core@1/pure/Map";
import MerkleNode "./MerkleNode";
import BlobRef "./BlobRef";
import Commit "./Commit";
import MerkleSearchTree "./MerkleSearchTree";
import Runtime "mo:core@1/Runtime";
import Result "mo:core@1/Result";
import Iter "mo:core@1/Iter";
import TextX "mo:xtended-text@2/TextX";
import List "mo:core@1/List";
import Set "mo:core@1/Set";
import Nat8 "mo:core@1/Nat8";
import Text "mo:core@1/Text";
import Char "mo:core@1/Char";
import CIDBuilder "./CIDBuilder";

module {

  public type MetaData = {
    head : CID.CID; // CID of the latest commit
    rev : TID.TID; // TID timestamp of the latest commit
    active : Bool;
    status : ?Text; // Optional status if not active
  };

  public type Repository = MetaData and {
    commits : PureMap.Map<TID.TID, Commit.Commit>;
    records : PureMap.Map<CID.CID, DagCbor.Value>;
    nodes : PureMap.Map<CID.CID, MerkleNode.Node>;
    blobs : PureMap.Map<CID.CID, BlobRef.BlobRef>;
  };

  public type Key = {
    collection : Text;
    recordKey : Text;
  };

  public type RecordData = {
    cid : CID.CID;
    value : DagCbor.Value;
  };

  public type WriteOperation = {
    #create : {
      key : Key;
      value : DagCbor.Value;
    };
    #update : {
      key : Key;
      value : DagCbor.Value;
    };
    #delete : {
      key : Key;
    };
  };

  public type WriteResult = {
    #create : {
      key : Key;
      cid : CID.CID;
    };
    #update : {
      key : Key;
      cid : CID.CID;
    };
    #delete : {
      key : Key;
      cid : CID.CID;
    };
  };

  public func empty(
    did : DID.Plc.DID,
    rev : TID.TID,
    signFunc : (Blob) -> async* Result.Result<Blob, Text>,
  ) : async* Result.Result<Repository, Text> {

    let mst = MerkleSearchTree.empty();
    let signedCommit = switch (
      await* createCommit(
        did,
        rev,
        mst.root,
        null,
        signFunc,
      )
    ) {
      case (#ok(commit)) commit;
      case (#err(e)) return #err("Failed to create commit: " # e);
    };
    let signedCommitCID = CIDBuilder.fromCommit(signedCommit);
    #ok({
      head = signedCommitCID;
      rev = rev;
      active = true;
      status = null;
      commits = PureMap.singleton<TID.TID, Commit.Commit>(rev, signedCommit);
      records = PureMap.empty<CID.CID, DagCbor.Value>();
      nodes = mst.nodes;
      blobs = PureMap.empty<CID.CID, BlobRef.BlobRef>();
    });
  };

  public func recordKeys(repository : Repository) : Iter.Iter<Key> {
    let mst = buildMerkleSearchTree(repository);
    MerkleSearchTree.keys(mst)
    |> Iter.map(
      _,
      func(key : Text) : Key {
        switch (keyFromText(key)) {
          case (null) Runtime.trap("Invalid key format in MerkleSearchTree: " # key);
          case (?k) k;
        };
      },
    );
  };

  public func recordEntries(repository : Repository) : Iter.Iter<(Key, RecordData)> {
    let mst = buildMerkleSearchTree(repository);
    MerkleSearchTree.entries(mst)
    |> Iter.map<(Text, CID.CID), (Key, RecordData)>(
      _,
      func((keyText, value) : (Text, CID.CID)) : (Key, RecordData) {
        let ?recordValue = PureMap.get(repository.records, CIDBuilder.compare, value) else Runtime.trap("Invalid repository. Record CID not found in records: " # CID.toText(value));

        let key = switch (keyFromText(keyText)) {
          case (null) Runtime.trap("Invalid key format in MerkleSearchTree: " # keyText);
          case (?k) k;
        };
        (
          key,
          {
            cid = value;
            value = recordValue;
          },
        );
      },
    );
  };

  public func recordEntriesByCollection(repository : Repository, collection : Text) : Iter.Iter<(Key, RecordData)> {

    recordEntries(repository)
    |> Iter.filter(
      _,
      func((key, data) : (Key, RecordData)) : Bool {
        key.collection == collection;
      },
    );
  };

  public func collectionKeys(repository : Repository) : Iter.Iter<Text> {
    let collections = Set.empty<Text>();
    for (key in recordKeys(repository)) {
      Set.add(collections, Text.compare, key.collection);
    };
    Set.values(collections);
  };

  public func getRecord(repository : Repository, key : Key) : ?RecordData {
    let path = keyToText(key);

    let mst = buildMerkleSearchTree(repository);

    let ?recordCID = MerkleSearchTree.get(mst, path) else return null;
    let ?value = PureMap.get(repository.records, CIDBuilder.compare, recordCID) else Runtime.trap("Invalid repository. Record CID not found in records: " # CID.toText(recordCID));
    ?{
      cid = recordCID;
      value = value;
    };
  };

  public func createRecord(
    repository : Repository,
    key : Key,
    value : DagCbor.Value,
    did : DID.Plc.DID,
    rev : TID.TID,
    signFunc : (Blob) -> async* Result.Result<Blob, Text>,
  ) : async* Result.Result<(Repository, CID.CID), Text> {
    let recordCID = CIDBuilder.fromRecord(key.recordKey, value);

    // Create record path
    let path = switch (keyToTextAndValidate(key)) {
      case (#ok(p)) p;
      case (#err(e)) return #err(e);
    };

    let mst = buildMerkleSearchTree(repository);

    // Add to MST
    let newMst = switch (MerkleSearchTree.add(mst, path, recordCID)) {
      case (#ok(mst)) mst;
      case (#err(e)) return #err("Failed to add to MST: " # debug_show (e));
    };

    let newRecords = PureMap.add(
      repository.records,
      CIDBuilder.compare,
      recordCID,
      value,
    );

    let newRepository = switch (
      await* commitNewData(
        repository,
        mst,
        newMst,
        newRecords,
        did,
        rev,
        signFunc,
      )
    ) {
      case (#ok(repo)) repo;
      case (#err(e)) return #err(e);
    };
    #ok((newRepository, recordCID));
  };

  public func putRecord(
    repository : Repository,
    key : Key,
    value : DagCbor.Value,
    did : DID.Plc.DID,
    rev : TID.TID,
    signFunc : (Blob) -> async* Result.Result<Blob, Text>,
  ) : async* Result.Result<(Repository, CID.CID), Text> {

    let recordCID = CIDBuilder.fromRecord(key.recordKey, value);

    // Create record path
    let path = switch (keyToTextAndValidate(key)) {
      case (#ok(p)) p;
      case (#err(e)) return #err(e);
    };

    let mst = buildMerkleSearchTree(repository);
    // Update MST (this will replace existing record)
    let newMst = switch (MerkleSearchTree.put(mst, path, recordCID)) {
      case (#ok(mst)) mst;
      case (#err(e)) return #err("Failed to update MST: " # debug_show (e));
    };

    let newRecords = PureMap.add(
      repository.records,
      CIDBuilder.compare,
      recordCID,
      value,
    );

    let newRepository = switch (
      await* commitNewData(
        repository,
        mst,
        newMst,
        newRecords,
        did,
        rev,
        signFunc,
      )
    ) {
      case (#ok(repo)) repo;
      case (#err(e)) return #err(e);
    };

    #ok((newRepository, recordCID));
  };

  public func deleteRecord(
    repository : Repository,
    key : Key,
    did : DID.Plc.DID,
    rev : TID.TID,
    signFunc : (Blob) -> async* Result.Result<Blob, Text>,
  ) : async* Result.Result<(Repository, CID.CID), Text> {
    let path = keyToText(key);

    let mst = buildMerkleSearchTree(repository);
    // Remove from MST
    let (newMst, removedValue) = switch (MerkleSearchTree.remove(mst, path)) {
      case (#ok((mst, removedValue))) (mst, removedValue);
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
        did,
        rev,
        signFunc,
      )
    ) {
      case (#ok(repo)) repo;
      case (#err(e)) return #err(e);
    };
    #ok((newRepository, removedValue));
  };

  public func applyWrites(
    repository : Repository,
    writeOperations : [WriteOperation],
    did : DID.Plc.DID,
    rev : TID.TID,
    signFunc : (Blob) -> async* Result.Result<Blob, Text>,
  ) : async* Result.Result<(Repository, [WriteResult]), Text> {

    var updatedRecords = repository.records;
    let mst = buildMerkleSearchTree(repository);
    var newMst = mst;

    // Process all write operations and collect results
    let results = List.empty<WriteResult>();

    for (writeOp in writeOperations.vals()) {
      let result : WriteResult = switch (writeOp) {
        case (#create(createOp)) {
          // TODO consolidate with createRecord
          let recordCID = CIDBuilder.fromRecord(createOp.key.recordKey, createOp.value);
          updatedRecords := PureMap.add(updatedRecords, CIDBuilder.compare, recordCID, createOp.value);

          // Create record path for MST
          let path = switch (keyToTextAndValidate(createOp.key)) {
            case (#ok(p)) p;
            case (#err(e)) return #err("Key validation failed: " # e);
          };

          // Add to MST
          newMst := switch (MerkleSearchTree.add(newMst, path, recordCID)) {
            case (#ok(mst)) mst;
            case (#err(e)) return #err("Failed to add to MST: " # debug_show (e));
          };

          #create({
            key = createOp.key;
            cid = recordCID;
          });
        };
        case (#update(updateOp)) {
          // TODO consolidate with putRecord
          let recordCID = CIDBuilder.fromRecord(updateOp.key.recordKey, updateOp.value);
          updatedRecords := PureMap.add(updatedRecords, CIDBuilder.compare, recordCID, updateOp.value);

          // Create record path for MST
          let path = switch (keyToTextAndValidate(updateOp.key)) {
            case (#ok(p)) p;
            case (#err(e)) return #err("Key validation failed: " # e);
          };
          // Update MST (this will replace existing record)
          newMst := switch (MerkleSearchTree.put(newMst, path, recordCID)) {
            case (#ok(mst)) mst;
            case (#err(e)) return #err("Failed to update MST: " # debug_show (e));
          };

          #update({
            key = updateOp.key;
            cid = recordCID;
          });
        };
        case (#delete(deleteOp)) {
          // TODO consolidate with deleteRecord
          let path = keyToText(deleteOp.key);

          // Remove from MST
          let (updatedMst, removedValue) = switch (MerkleSearchTree.remove(newMst, path)) {
            case (#ok((mst, removedValue))) (mst, removedValue);
            case (#err(e)) return #err("Failed to remove from MST: " # debug_show (e));
          };
          newMst := updatedMst;

          #delete({
            key = deleteOp.key;
            cid = removedValue;
          });
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
        did,
        rev,
        signFunc,
      )
    ) {
      case (#ok(repo)) repo;
      case (#err(e)) return #err(e);
    };
    #ok((newRepository, List.toArray(results)));
  };

  public func keyFromText(key : Text) : ?Key {
    let parts = Text.split(key, #char('/'));
    let ?collection = parts.next() else return null;
    let ?initialRecordKey = parts.next() else return null;
    var recordKey = initialRecordKey;
    // Incase the rkey contains slashes, join the rest back
    label l loop {
      let ?part = parts.next() else break l;
      recordKey #= part;
    };
    ?{
      collection = collection;
      recordKey = recordKey;
    };
  };

  public func keyToText(key : Key) : Text {
    key.collection # "/" # key.recordKey;
  };

  private func commitNewData(
    repository : Repository,
    mst : MerkleSearchTree.MerkleSearchTree,
    newMst : MerkleSearchTree.MerkleSearchTree,
    newRecords : PureMap.Map<CID.CID, DagCbor.Value>,
    did : DID.Plc.DID,
    rev : TID.TID,
    signFunc : (Blob) -> async* Result.Result<Blob, Text>,
  ) : async* Result.Result<Repository, Text> {

    let signedCommit = switch (
      await* createCommit(
        did,
        rev,
        newMst.root,
        ?mst.root,
        signFunc,
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
      rev,
      signedCommit,
    );

    let newRepository : Repository = {
      repository with
      head = commitCID;
      rev = rev;
      commits = updatedCommits;
      nodes = newMst.nodes;
      records = newRecords;
    };
    #ok(newRepository);
  };

  private func createCommit(
    did : DID.Plc.DID,
    rev : TID.TID,
    newNodeCID : CID.CID,
    lastNodeCID : ?CID.CID,
    signFunc : (Blob) -> async* Result.Result<Blob, Text>,
  ) : async* Result.Result<Commit.Commit, Text> {

    let unsignedCommit : Commit.UnsignedCommit = {
      did = did;
      version = 3; // TODO?
      data = newNodeCID;
      rev = rev;
      prev = lastNodeCID;
    };

    // Sign commit
    switch (await* signCommit(unsignedCommit, signFunc)) {
      case (#ok(commit)) #ok(commit);
      case (#err(e)) return #err("Failed to sign commit: " # e);
    };
  };

  private func signCommit(
    unsigned : Commit.UnsignedCommit,
    signFunc : (Blob) -> async* Result.Result<Blob, Text>,
  ) : async* Result.Result<Commit.Commit, Text> {
    // Serialize unsigned commit to CBOR
    let cid = CIDBuilder.fromUnsignedCommit(unsigned);
    let hash = CID.getHash(cid);

    // Sign with rotation key
    let signature = switch (await* signFunc(hash)) {
      case (#ok(sig)) sig;
      case (#err(e)) return #err(e);
    };

    #ok({
      unsigned with
      sig = signature;
    });
  };

  // Validate key format
  private func keyToTextAndValidate(key : Key) : Result.Result<Text, Text> {

    // Check for empty parts
    if (TextX.isEmptyOrWhitespace(key.collection)) {
      return #err("Collection name must be non-empty");
    };
    if (TextX.isEmptyOrWhitespace(key.recordKey)) {
      return #err("Record key must be non-empty");
    };

    // Validate collection as NSID (reversed domain notation)
    if (not isValidNSID(key.collection)) {
      return #err("Invalid NSID format in collection: " # key.collection);
    };

    // Validate rkey constraints
    if (key.recordKey.size() > 512) {
      return #err("Record key exceeds 512 character limit");
    };
    if (key.recordKey == "." or key.recordKey == "..") {
      return #err("Record key cannot be '.' or '..'");
    };

    // Validate rkey characters
    for (char in key.recordKey.chars()) {
      if (not isValidRkeyChar(char)) {
        return #err("Invalid character in record key: " # Text.fromChar(char));
      };
    };

    #ok(keyToText(key));
  };

  private func isValidRkeyChar(c : Char) : Bool {
    (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '.' or c == '-' or c == '_' or c == '~' or c == ':';
  };

  private func isValidNSID(nsid : Text) : Bool {
    // Basic NSID validation: alphanumeric + dots, must have at least one dot
    // Format: authority.name (e.g., com.example.record)
    if (nsid.size() == 0 or nsid.size() > 317) {
      // NSID max length
      return false;
    };

    var hasDot = false;
    for (char in nsid.chars()) {
      if (char == '.') {
        hasDot := true;
      } else if (not ((char >= 'a' and char <= 'z') or (char >= '0' and char <= '9') or char == '-')) {
        return false;
      };
    };

    // Must contain at least one dot and not start/end with dot
    hasDot and not Text.startsWith(nsid, #char('.')) and not Text.endsWith(nsid, #char('.'));
  };

  private func buildMerkleSearchTree(repository : Repository) : MerkleSearchTree.MerkleSearchTree {
    // Get current commit to find root node
    let ?currentCommit = PureMap.get(
      repository.commits,
      TID.compare,
      repository.rev,
    ) else {
      Runtime.trap("Current commit not found in repository");
    };
    {
      root = currentCommit.data;
      nodes = repository.nodes;
    };
  };

};
