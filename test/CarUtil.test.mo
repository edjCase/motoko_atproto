import Debug "mo:core@1/Debug";
import Result "mo:core@1/Result";
import Runtime "mo:core@1/Runtime";
import DID "mo:did@3";
import TID "mo:tid@1";
import Blob "mo:core@1/Blob";
import DagCbor "mo:dag-cbor@2";
import { test = testAsync } "mo:test/async";
import Repository "../src/atproto/Repository";
import Sha256 "mo:sha2@0/Sha256";
import CarUtil "../src/pds/CarUtil";

// Helper to create test TID
func createTestTID(timestamp : Nat) : TID.TID {
  {
    timestamp = timestamp;
    clockId = 0;
  };
};

// Mock signing function for tests
func mockSignFunc(data : Blob) : async* Result.Result<Blob, Text> {
  // Return a deterministic "signature" for testing
  let hash = Sha256.fromBlob(#sha256, data);
  #ok(hash);
};

// Helper to create simple CBOR value
func createTestValue(text : Text) : DagCbor.Value {
  #map([
    ("type", #text("test.record")),
    ("value", #text(text)),
  ]);
};

await testAsync(
  "from/buildRepository",
  func() : async () {

    let repoId : DID.Plc.DID = { identifier = "test123456789abcdefghijk" };
    var repository : Repository.Repository = switch (await* Repository.empty(repoId, createTestTID(1000000), mockSignFunc)) {
      case (#ok(r)) r;
      case (#err(e)) Runtime.trap("Setup failed: " # e);
    };

    let firstTID = createTestTID(1000001);

    let (newRepository, _) = switch (
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

    let (newRepository2, _) = switch (
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

    let carFile = switch (CarUtil.fromRepository(repository, null)) {
      case (#err(err)) Runtime.trap("Error creating CAR file: " # err);
      case (#ok(carFile)) carFile;
    };
    switch (CarUtil.toRepository(carFile)) {
      case (#err(err)) Runtime.trap("Error building repository: " # err);
      case (#ok((actualRepoId, actualRepo))) {
        if (repoId != actualRepoId) {
          Runtime.trap("Root CIDs do not match");
        };
        let expectedData = Repository.exportData(repository, null);
        let actualData = Repository.exportData(actualRepo, null);
        if (expectedData != actualData) {
          Runtime.trap("Repository data does not match");
        };
      };
    };
  },
);
