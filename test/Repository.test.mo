import Result "mo:core@1/Result";
import Runtime "mo:core@1/Runtime";
import CID "mo:cid@1";
import DID "mo:did@3";
import TID "mo:tid@1";
import Blob "mo:core@1/Blob";
import Array "mo:core@1/Array";
import Iter "mo:core@1/Iter";
import DagCbor "mo:dag-cbor@2";
import { test } "mo:test";
import { test = testAsync } "mo:test/async";
import Repository "../src/atproto/Repository";
import Sha256 "mo:sha2@0/Sha256";

// Mock signing function for tests
func mockSignFunc(data : Blob) : async* Result.Result<Blob, Text> {
  // Return a deterministic "signature" for testing
  let hash = Sha256.fromBlob(#sha256, data);
  #ok(hash);
};

// Helper to create test DID
func createTestDID() : DID.Plc.DID {
  { identifier = "test123456789abcdefghijk" };
};

// Helper to create test TID
func createTestTID(timestamp : Nat) : TID.TID {
  {
    timestamp = timestamp;
    clockId = 0;
  };
};

// Helper to create simple CBOR value
func createTestValue(text : Text) : DagCbor.Value {
  #map([
    ("type", #text("test.record")),
    ("value", #text(text)),
  ]);
};

await testAsync(
  "Repository - Record Entries By Collection",
  func() : async () {
    let did = createTestDID();
    let tid1 = createTestTID(1000000);

    var repo = switch (await* Repository.empty(did, tid1, mockSignFunc)) {
      case (#ok(r)) r;
      case (#err(e)) Runtime.trap("Setup failed: " # e);
    };

    // Create records in different collections
    let keys = [
      { collection = "app.bsky.feed.post"; recordKey = "post1" },
      { collection = "app.bsky.feed.post"; recordKey = "post2" },
      { collection = "app.bsky.feed.like"; recordKey = "like1" },
    ];

    for ((i, key) in Iter.enumerate(keys.vals())) {
      let value = createTestValue("test");
      let tid = createTestTID(1000001 + i);
      repo := switch (await* Repository.createRecord(repo, key, value, did, tid, mockSignFunc)) {
        case (#ok((r, _))) r;
        case (#err(e)) Runtime.trap("Create failed: " # e);
      };
    };

    // Get entries for specific collection
    let postEntries = Iter.toArray(
      Repository.recordEntriesByCollection(repo, "app.bsky.feed.post")
    );
    if (postEntries.size() != 2) {
      Runtime.trap("Expected 2 post entries, got " # debug_show (postEntries.size()));
    };

    let likeEntries = Iter.toArray(
      Repository.recordEntriesByCollection(repo, "app.bsky.feed.like")
    );
    if (likeEntries.size() != 1) {
      Runtime.trap("Expected 1 like entry, got " # debug_show (likeEntries.size()));
    };
  },
);

await testAsync(
  "Repository - Empty Repository Creation",
  func() : async () {
    let did = createTestDID();
    let tid = createTestTID(1000000);

    switch (await* Repository.empty(did, tid, mockSignFunc)) {
      case (#ok(repo)) {
        if (repo.rev != tid) {
          Runtime.trap("Rev mismatch in empty repository");
        };
        if (not repo.active) {
          Runtime.trap("Empty repository should be active");
        };
        if (repo.status != null) {
          Runtime.trap("Empty repository should have no status");
        };
      };
      case (#err(e)) Runtime.trap("Failed to create empty repository: " # e);
    };
  },
);

await testAsync(
  "Repository - Create Single Record",
  func() : async () {
    let did = createTestDID();
    let tid1 = createTestTID(1000000);

    let repo = switch (await* Repository.empty(did, tid1, mockSignFunc)) {
      case (#ok(r)) r;
      case (#err(e)) Runtime.trap("Failed to create repository: " # e);
    };

    let key : Repository.Key = {
      collection = "app.bsky.feed.post";
      recordKey = "record1";
    };
    let value = createTestValue("test post");
    let tid2 = createTestTID(1000001);

    switch (await* Repository.createRecord(repo, key, value, did, tid2, mockSignFunc)) {
      case (#ok((updatedRepo, cid))) {
        // Verify record exists
        switch (Repository.getRecord(updatedRepo, key)) {
          case (?recordData) {
            if (recordData.cid != cid) {
              Runtime.trap("Record CID mismatch");
            };
          };
          case (null) Runtime.trap("Created record not found");
        };

        // Verify rev updated
        if (updatedRepo.rev != tid2) {
          Runtime.trap("Repository rev not updated after create");
        };
      };
      case (#err(e)) Runtime.trap("Failed to create record: " # e);
    };
  },
);

await testAsync(
  "Repository - Create Duplicate Record Fails",
  func() : async () {
    let did = createTestDID();
    let tid1 = createTestTID(1000000);

    let repo = switch (await* Repository.empty(did, tid1, mockSignFunc)) {
      case (#ok(r)) r;
      case (#err(e)) Runtime.trap("Setup failed: " # e);
    };

    let key : Repository.Key = {
      collection = "app.bsky.feed.post";
      recordKey = "duplicate";
    };
    let value = createTestValue("first");
    let tid2 = createTestTID(1000001);

    let repo2 = switch (await* Repository.createRecord(repo, key, value, did, tid2, mockSignFunc)) {
      case (#ok((r, _))) r;
      case (#err(e)) Runtime.trap("First create failed: " # e);
    };

    let tid3 = createTestTID(1000002);
    switch (await* Repository.createRecord(repo2, key, value, did, tid3, mockSignFunc)) {
      case (#ok(_)) Runtime.trap("Should fail to create duplicate record");
      case (#err(_)) {}; // Expected
    };
  },
);

await testAsync(
  "Repository - Put Record (Update)",
  func() : async () {
    let did = createTestDID();
    let tid1 = createTestTID(1000000);

    let repo = switch (await* Repository.empty(did, tid1, mockSignFunc)) {
      case (#ok(r)) r;
      case (#err(e)) Runtime.trap("Setup failed: " # e);
    };

    let key : Repository.Key = {
      collection = "app.bsky.feed.post";
      recordKey = "update-test";
    };
    let value1 = createTestValue("original");
    let tid2 = createTestTID(1000001);

    let repo2 = switch (await* Repository.createRecord(repo, key, value1, did, tid2, mockSignFunc)) {
      case (#ok((r, _))) r;
      case (#err(e)) Runtime.trap("Create failed: " # e);
    };

    // Update with put
    let value2 = createTestValue("updated");
    let tid3 = createTestTID(1000002);

    switch (
      await* Repository.putRecord(
        repo2,
        key,
        value2,
        did,
        tid3,
        mockSignFunc,
      )
    ) {
      case (#ok((updatedRepo, newCid))) {
        switch (Repository.getRecord(updatedRepo, key)) {
          case (?recordData) {
            if (recordData.cid != newCid) {
              Runtime.trap("Updated CID mismatch\nExpected: " # CID.toText(newCid) # "\nActual:   " # CID.toText(recordData.cid));
            };
          };
          case (null) Runtime.trap("Updated record not found");
        };
      };
      case (#err(e)) Runtime.trap("Put failed: " # e);
    };
  },
);

await testAsync(
  "Repository - Delete Record",
  func() : async () {
    let did = createTestDID();
    let tid1 = createTestTID(1000000);

    let repo = switch (await* Repository.empty(did, tid1, mockSignFunc)) {
      case (#ok(r)) r;
      case (#err(e)) Runtime.trap("Setup failed: " # e);
    };

    let key : Repository.Key = {
      collection = "app.bsky.feed.post";
      recordKey = "delete-test";
    };
    let value = createTestValue("to delete");
    let tid2 = createTestTID(1000001);

    let repo2 = switch (await* Repository.createRecord(repo, key, value, did, tid2, mockSignFunc)) {
      case (#ok((r, _))) r;
      case (#err(e)) Runtime.trap("Create failed: " # e);
    };

    let tid3 = createTestTID(1000002);
    switch (await* Repository.deleteRecord(repo2, key, did, tid3, mockSignFunc)) {
      case (#ok((updatedRepo, _))) {
        // Verify record is gone
        switch (Repository.getRecord(updatedRepo, key)) {
          case (?_) Runtime.trap("Deleted record still exists");
          case (null) {}; // Expected
        };
      };
      case (#err(e)) Runtime.trap("Delete failed: " # e);
    };
  },
);

await testAsync(
  "Repository - Delete Non-Existent Record Fails",
  func() : async () {
    let did = createTestDID();
    let tid1 = createTestTID(1000000);

    let repo = switch (await* Repository.empty(did, tid1, mockSignFunc)) {
      case (#ok(r)) r;
      case (#err(e)) Runtime.trap("Setup failed: " # e);
    };

    let key : Repository.Key = {
      collection = "app.bsky.feed.post";
      recordKey = "nonexistent";
    };
    let tid2 = createTestTID(1000001);

    switch (await* Repository.deleteRecord(repo, key, did, tid2, mockSignFunc)) {
      case (#ok(_)) Runtime.trap("Should fail to delete non-existent record");
      case (#err(_)) {}; // Expected
    };
  },
);

await testAsync(
  "Repository - Multiple Records in Same Collection",
  func() : async () {
    let did = createTestDID();
    let tid1 = createTestTID(1000000);

    var repo = switch (await* Repository.empty(did, tid1, mockSignFunc)) {
      case (#ok(r)) r;
      case (#err(e)) Runtime.trap("Setup failed: " # e);
    };

    let collection = "app.bsky.feed.post";
    let keys = ["post1", "post2", "post3"];

    // Create multiple records
    for ((i, rkey) in Iter.enumerate(keys.vals())) {
      let key : Repository.Key = {
        collection = collection;
        recordKey = rkey;
      };
      let value = createTestValue("post " # rkey);
      let tid = createTestTID(1000001 + i);

      repo := switch (await* Repository.createRecord(repo, key, value, did, tid, mockSignFunc)) {
        case (#ok((r, _))) r;
        case (#err(e)) Runtime.trap("Failed to create " # rkey # ": " # e);
      };
    };

    // Verify all records exist
    for (rkey in keys.vals()) {
      let key : Repository.Key = {
        collection = collection;
        recordKey = rkey;
      };
      switch (Repository.getRecord(repo, key)) {
        case (?_) {}; // Good
        case (null) Runtime.trap("Record not found: " # rkey);
      };
    };
  },
);

await testAsync(
  "Repository - Records in Different Collections",
  func() : async () {
    let did = createTestDID();
    let tid1 = createTestTID(1000000);

    var repo = switch (await* Repository.empty(did, tid1, mockSignFunc)) {
      case (#ok(r)) r;
      case (#err(e)) Runtime.trap("Setup failed: " # e);
    };

    let collections = [
      "app.bsky.feed.post",
      "app.bsky.feed.like",
      "app.bsky.graph.follow",
    ];

    for ((i, coll) in Iter.enumerate(collections.vals())) {
      let key : Repository.Key = {
        collection = coll;
        recordKey = "record1";
      };
      let value = createTestValue(coll);
      let tid = createTestTID(1000001 + i);

      repo := switch (await* Repository.createRecord(repo, key, value, did, tid, mockSignFunc)) {
        case (#ok((r, _))) r;
        case (#err(e)) Runtime.trap("Failed to create in " # coll # ": " # e);
      };
    };

    // Verify all records exist
    for (coll in collections.vals()) {
      let key : Repository.Key = {
        collection = coll;
        recordKey = "record1";
      };
      switch (Repository.getRecord(repo, key)) {
        case (?_) {}; // Good
        case (null) Runtime.trap("Record not found in: " # coll);
      };
    };
  },
);

await testAsync(
  "Repository - Record Keys Iterator",
  func() : async () {
    let did = createTestDID();
    let tid1 = createTestTID(1000000);

    var repo = switch (await* Repository.empty(did, tid1, mockSignFunc)) {
      case (#ok(r)) r;
      case (#err(e)) Runtime.trap("Setup failed: " # e);
    };

    let expectedKeys = [
      { collection = "app.bsky.feed.post"; recordKey = "post1" },
      { collection = "app.bsky.feed.post"; recordKey = "post2" },
      { collection = "app.bsky.feed.like"; recordKey = "like1" },
    ];

    for ((i, key) in Iter.enumerate(expectedKeys.vals())) {
      let value = createTestValue("test");
      let tid = createTestTID(1000001 + i);
      repo := switch (await* Repository.createRecord(repo, key, value, did, tid, mockSignFunc)) {
        case (#ok((r, _))) r;
        case (#err(e)) Runtime.trap("Create failed: " # e);
      };
    };

    let keys = Iter.toArray(Repository.recordKeys(repo));
    if (keys.size() != expectedKeys.size()) {
      Runtime.trap("Key count mismatch");
    };
  },
);

await testAsync(
  "Repository - Record Entries Iterator",
  func() : async () {
    let did = createTestDID();
    let tid1 = createTestTID(1000000);

    var repo = switch (await* Repository.empty(did, tid1, mockSignFunc)) {
      case (#ok(r)) r;
      case (#err(e)) Runtime.trap("Setup failed: " # e);
    };

    let key : Repository.Key = {
      collection = "app.bsky.feed.post";
      recordKey = "test";
    };
    let value = createTestValue("content");
    let tid2 = createTestTID(1000001);

    repo := switch (await* Repository.createRecord(repo, key, value, did, tid2, mockSignFunc)) {
      case (#ok((r, _))) r;
      case (#err(e)) Runtime.trap("Create failed: " # e);
    };

    let entries = Iter.toArray(Repository.recordEntries(repo));
    if (entries.size() != 1) {
      Runtime.trap("Expected 1 entry, got " # debug_show (entries.size()));
    };

    let (entryKey, _) = entries[0];
    if (entryKey.collection != key.collection or entryKey.recordKey != key.recordKey) {
      Runtime.trap("Entry key mismatch");
    };
  },
);

await testAsync(
  "Repository - Record Entries By Collection",
  func() : async () {
    let did = createTestDID();
    let tid1 = createTestTID(1000000);

    var repo = switch (await* Repository.empty(did, tid1, mockSignFunc)) {
      case (#ok(r)) r;
      case (#err(e)) Runtime.trap("Setup failed: " # e);
    };

    // Create records in different collections
    let keys = [
      { collection = "app.bsky.feed.post"; recordKey = "post1" },
      { collection = "app.bsky.feed.post"; recordKey = "post2" },
      { collection = "app.bsky.feed.like"; recordKey = "like1" },
    ];

    for ((i, key) in Iter.enumerate(keys.vals())) {
      let value = createTestValue("test");
      let tid = createTestTID(1000001 + i);
      repo := switch (await* Repository.createRecord(repo, key, value, did, tid, mockSignFunc)) {
        case (#ok((r, _))) r;
        case (#err(e)) Runtime.trap("Create failed: " # e);
      };
    };

    // Get entries for specific collection
    let postEntries = Iter.toArray(
      Repository.recordEntriesByCollection(repo, "app.bsky.feed.post")
    );
    if (postEntries.size() != 2) {
      Runtime.trap("Expected 2 post entries, got " # debug_show (postEntries.size()));
    };

    let likeEntries = Iter.toArray(
      Repository.recordEntriesByCollection(repo, "app.bsky.feed.like")
    );
    if (likeEntries.size() != 1) {
      Runtime.trap("Expected 1 like entry, got " # debug_show (likeEntries.size()));
    };
  },
);

await testAsync(
  "Repository - Collection Keys Iterator",
  func() : async () {
    let did = createTestDID();
    let tid1 = createTestTID(1000000);

    var repo = switch (await* Repository.empty(did, tid1, mockSignFunc)) {
      case (#ok(r)) r;
      case (#err(e)) Runtime.trap("Setup failed: " # e);
    };

    let collections = [
      "app.bsky.feed.post",
      "app.bsky.feed.like",
      "app.bsky.graph.follow",
    ];

    for ((i, coll) in Iter.enumerate(collections.vals())) {
      let key : Repository.Key = {
        collection = coll;
        recordKey = "test";
      };
      let value = createTestValue("test");
      let tid = createTestTID(1000001 + i);
      repo := switch (await* Repository.createRecord(repo, key, value, did, tid, mockSignFunc)) {
        case (#ok((r, _))) r;
        case (#err(e)) Runtime.trap("Create failed: " # e);
      };
    };

    let foundCollections = Iter.toArray(Repository.collectionKeys(repo));
    if (foundCollections.size() != collections.size()) {
      Runtime.trap("Collection count mismatch");
    };
  },
);

await testAsync(
  "Repository - Apply Writes Batch Create",
  func() : async () {
    let did = createTestDID();
    let tid1 = createTestTID(1000000);

    let repo = switch (await* Repository.empty(did, tid1, mockSignFunc)) {
      case (#ok(r)) r;
      case (#err(e)) Runtime.trap("Setup failed: " # e);
    };

    let writes : [Repository.WriteOperation] = [
      #create({
        key = { collection = "app.bsky.feed.post"; recordKey = "post1" };
        value = createTestValue("post1");
      }),
      #create({
        key = { collection = "app.bsky.feed.post"; recordKey = "post2" };
        value = createTestValue("post2");
      }),
      #create({
        key = { collection = "app.bsky.feed.like"; recordKey = "like1" };
        value = createTestValue("like1");
      }),
    ];

    let tid2 = createTestTID(1000001);
    switch (await* Repository.applyWrites(repo, writes, did, tid2, mockSignFunc)) {
      case (#ok((updatedRepo, results))) {
        if (results.size() != writes.size()) {
          Runtime.trap("Result count mismatch");
        };

        // Verify all records created
        for (write in writes.vals()) {
          switch (write) {
            case (#create(op)) {
              switch (Repository.getRecord(updatedRepo, op.key)) {
                case (?_) {}; // Good
                case (null) Runtime.trap("Batch created record not found");
              };
            };
            case (_) {};
          };
        };
      };
      case (#err(e)) Runtime.trap("Batch write failed: " # e);
    };
  },
);

await testAsync(
  "Repository - Apply Writes Mixed Operations",
  func() : async () {
    let did = createTestDID();
    let tid1 = createTestTID(1000000);

    var repo = switch (await* Repository.empty(did, tid1, mockSignFunc)) {
      case (#ok(r)) r;
      case (#err(e)) Runtime.trap("Setup failed: " # e);
    };

    // Create initial record
    let key : Repository.Key = {
      collection = "app.bsky.feed.post";
      recordKey = "existing";
    };
    let tid2 = createTestTID(1000001);
    repo := switch (await* Repository.createRecord(repo, key, createTestValue("old"), did, tid2, mockSignFunc)) {
      case (#ok((r, _))) r;
      case (#err(e)) Runtime.trap("Setup create failed: " # e);
    };

    // Apply mixed operations
    let writes : [Repository.WriteOperation] = [
      #create({
        key = { collection = "app.bsky.feed.post"; recordKey = "new" };
        value = createTestValue("new");
      }),
      #update({
        key = key;
        value = createTestValue("updated");
      }),
    ];

    let tid3 = createTestTID(1000002);
    switch (await* Repository.applyWrites(repo, writes, did, tid3, mockSignFunc)) {
      case (#ok((updatedRepo, results))) {
        if (results.size() != 2) {
          Runtime.trap("Expected 2 results");
        };

        // Verify new record exists
        switch (Repository.getRecord(updatedRepo, { collection = "app.bsky.feed.post"; recordKey = "new" })) {
          case (?_) {}; // Good
          case (null) Runtime.trap("New record not found");
        };

        // Verify existing record was updated
        switch (Repository.getRecord(updatedRepo, key)) {
          case (?_) {}; // Good
          case (null) Runtime.trap("Updated record not found");
        };
      };
      case (#err(e)) Runtime.trap("Mixed batch failed: " # e);
    };
  },
);

await testAsync(
  "Repository - Apply Writes with Delete",
  func() : async () {
    let did = createTestDID();
    let tid1 = createTestTID(1000000);

    var repo = switch (await* Repository.empty(did, tid1, mockSignFunc)) {
      case (#ok(r)) r;
      case (#err(e)) Runtime.trap("Setup failed: " # e);
    };

    // Create record to delete
    let key : Repository.Key = {
      collection = "app.bsky.feed.post";
      recordKey = "todelete";
    };
    let tid2 = createTestTID(1000001);
    repo := switch (await* Repository.createRecord(repo, key, createTestValue("temp"), did, tid2, mockSignFunc)) {
      case (#ok((r, _))) r;
      case (#err(e)) Runtime.trap("Setup create failed: " # e);
    };

    let writes : [Repository.WriteOperation] = [
      #delete({ key = key }),
    ];

    let tid3 = createTestTID(1000002);
    switch (await* Repository.applyWrites(repo, writes, did, tid3, mockSignFunc)) {
      case (#ok((updatedRepo, _))) {
        // Verify record is deleted
        switch (Repository.getRecord(updatedRepo, key)) {
          case (?_) Runtime.trap("Deleted record still exists");
          case (null) {}; // Expected
        };
      };
      case (#err(e)) Runtime.trap("Delete batch failed: " # e);
    };
  },
);

await testAsync(
  "Repository - Key Format Validation - Empty Collection",
  func() : async () {
    let did = createTestDID();
    let tid1 = createTestTID(1000000);

    let repo = switch (await* Repository.empty(did, tid1, mockSignFunc)) {
      case (#ok(r)) r;
      case (#err(e)) Runtime.trap("Setup failed: " # e);
    };

    let key : Repository.Key = {
      collection = "";
      recordKey = "test";
    };
    let tid2 = createTestTID(1000001);

    switch (await* Repository.createRecord(repo, key, createTestValue("test"), did, tid2, mockSignFunc)) {
      case (#ok(_)) Runtime.trap("Should reject empty collection");
      case (#err(_)) {}; // Expected
    };
  },
);

await testAsync(
  "Repository - Key Format Validation - Empty RecordKey",
  func() : async () {
    let did = createTestDID();
    let tid1 = createTestTID(1000000);

    let repo = switch (await* Repository.empty(did, tid1, mockSignFunc)) {
      case (#ok(r)) r;
      case (#err(e)) Runtime.trap("Setup failed: " # e);
    };

    let key : Repository.Key = {
      collection = "app.bsky.feed.post";
      recordKey = "";
    };
    let tid2 = createTestTID(1000001);

    switch (await* Repository.createRecord(repo, key, createTestValue("test"), did, tid2, mockSignFunc)) {
      case (#ok(_)) Runtime.trap("Should reject empty recordKey");
      case (#err(_)) {}; // Expected
    };
  },
);

await testAsync(
  "Repository - Key Format Validation - Invalid NSID",
  func() : async () {
    let did = createTestDID();
    let tid1 = createTestTID(1000000);

    let repo = switch (await* Repository.empty(did, tid1, mockSignFunc)) {
      case (#ok(r)) r;
      case (#err(e)) Runtime.trap("Setup failed: " # e);
    };

    let key : Repository.Key = {
      collection = "invalid_nsid"; // No dots
      recordKey = "test";
    };
    let tid2 = createTestTID(1000001);

    switch (await* Repository.createRecord(repo, key, createTestValue("test"), did, tid2, mockSignFunc)) {
      case (#ok(_)) Runtime.trap("Should reject invalid NSID");
      case (#err(_)) {}; // Expected
    };
  },
);

test(
  "Repository - Key To/From Text Conversion",
  func() {
    let key : Repository.Key = {
      collection = "app.bsky.feed.post";
      recordKey = "abc123";
    };

    let text = Repository.keyToText(key);
    if (text != "app.bsky.feed.post/abc123") {
      Runtime.trap("Key to text conversion failed");
    };

    switch (Repository.keyFromText(text)) {
      case (?parsedKey) {
        if (parsedKey.collection != key.collection or parsedKey.recordKey != key.recordKey) {
          Runtime.trap("Key from text conversion failed");
        };
      };
      case (null) Runtime.trap("Failed to parse key text");
    };
  },
);

test(
  "Repository - Key With Slash In RecordKey",
  func() {
    let keyText = "app.bsky.feed.post/record/with/slashes";

    switch (Repository.keyFromText(keyText)) {
      case (?key) {
        if (key.collection != "app.bsky.feed.post") {
          Runtime.trap("Collection mismatch with slashes in rkey");
        };
        if (key.recordKey != "record/with/slashes") {
          Runtime.trap("RecordKey mismatch with slashes.\nExpected: 'record/with/slashes'\nActual:   '" # key.recordKey # "'");
        };
      };
      case (null) Runtime.trap("Failed to parse key with slashes");
    };
  },
);

await testAsync(
  "exportData",
  func() : async () {

    let repoId = createTestDID();
    var repository : Repository.Repository = switch (await* Repository.empty(repoId, createTestTID(1000000), mockSignFunc)) {
      case (#ok(r)) r;
      case (#err(e)) Runtime.trap("Setup failed: " # e);
    };

    let firstTID = createTestTID(1000001);

    let (newRepository, record1CID) = switch (
      await* Repository.createRecord(
        repository,
        { collection = "app.bsky.feed.post"; recordKey = "post1" },
        createTestValue("test post"),
        repoId,
        firstTID,
        mockSignFunc,
      )
    ) {
      case (#ok((r, cid))) (r, cid);
      case (#err(e)) Runtime.trap("Create failed: " # e);
    };
    repository := newRepository;

    let (newRepository2, record2CID) = switch (
      await* Repository.createRecord(
        repository,
        { collection = "app.bsky.feed.post"; recordKey = "post2" },
        createTestValue("another post"),
        repoId,
        createTestTID(1000002),
        mockSignFunc,
      )
    ) {
      case (#ok((r, cid))) (r, cid);
      case (#err(e)) Runtime.trap("Create failed: " # e);
    };
    repository := newRepository2;

    switch (Repository.exportData(repository, #full({ includeHistorical = false }))) {
      case (#ok(data)) {
        if (data.records.size() != 2) {
          Runtime.trap("full, no historical - Expected 2 records in export, got " # debug_show (data.records.size()));
        };
        if (not Array.any(data.records, func(r : (CID.CID, DagCbor.Value)) : Bool = r.0 == record1CID)) {
          Runtime.trap("full, no historical - Export missing record1 CID");
        };
        if (not Array.any(data.records, func(r : (CID.CID, DagCbor.Value)) : Bool = r.0 == record2CID)) {
          Runtime.trap("full, no historical - Export missing record2 CID");
        };
        if (data.commits.size() != 1) {
          Runtime.trap("full, no historical - Expected 1 commit in export, got " # debug_show (data.commits.size()));
        };
        if (data.nodes.size() != 1) {
          Runtime.trap("full, no historical - Expected exactly 1 node in export, got " # debug_show (data.nodes.size()));
        };
      };
      case (#err(e)) Runtime.trap("Export failed: " # e);
    };
    switch (Repository.exportData(repository, #full({ includeHistorical = true }))) {
      case (#ok(data)) {
        if (data.records.size() != 2) {
          Runtime.trap("full, historical - Expected 2 records in export, got " # debug_show (data.records.size()));
        };
        if (not Array.any(data.records, func(r : (CID.CID, DagCbor.Value)) : Bool = r.0 == record1CID)) {
          Runtime.trap("full, historical - Export missing record1 CID");
        };
        if (not Array.any(data.records, func(r : (CID.CID, DagCbor.Value)) : Bool = r.0 == record2CID)) {
          Runtime.trap("full, historical - Export missing record2 CID");
        };
        if (data.commits.size() != 3) {
          Runtime.trap("full, historical - Expected 3 commits in export, got " # debug_show (data.commits.size()));
        };
        if (data.nodes.size() != 3) {
          Runtime.trap("full, historical - Expected exactly 3 nodes in export, got " # debug_show (data.nodes.size()));
        };
      };
      case (#err(e)) Runtime.trap("Export failed: " # e);
    };

    switch (Repository.exportData(repository, #since(firstTID))) {
      case (#ok(data)) {
        if (data.records.size() != 1) {
          Runtime.trap("since - Expected 1 records in export, got " # debug_show (data.records.size()));
        };
        if (not Array.any(data.records, func(r : (CID.CID, DagCbor.Value)) : Bool = r.0 == record2CID)) {
          Runtime.trap("since - Export missing record2 CID");
        };
        if (data.commits.size() != 1) {
          Runtime.trap("since - Expected 1 commit in export, got " # debug_show (data.commits.size()));
        };
        if (data.nodes.size() != 1) {
          Runtime.trap("since - Expected exactly 1 node in export, got " # debug_show (data.nodes.size()));
        };
      };
      case (#err(e)) Runtime.trap("Export failed: " # e);
    };

  },
);
