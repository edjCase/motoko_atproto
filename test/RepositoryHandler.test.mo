import Result "mo:core@1/Result";
import Runtime "mo:core@1/Runtime";
import CID "mo:cid@1";
import DID "mo:did@3";
import TID "mo:tid@1";
import Blob "mo:core@1/Blob";
import { test = testAsync } "mo:test/async";
import RepositoryHandler "../src/pds/Handlers/RepositoryHandler";
import ServerInfoHandler "../src/pds/Handlers/ServerInfoHandler";
import KeyHandler "../src/pds/Handlers/KeyHandler";
import Repository "../src/atproto/Repository";
import Sha256 "mo:sha2@0/Sha256";
import DateTime "mo:datetime@1/DateTime";
import Array "mo:core@1/Array";

// Helper to create test DID
func createTestDID() : DID.Plc.DID {
  { identifier = "test123456789abcdefghijk" };
};

// Create mock handlers for testing
func createMockHandlers() : (KeyHandler.HandlerInterface, ServerInfoHandler.Handler, TID.Generator) {
  let keyHandler : KeyHandler.HandlerInterface = {
    sign = func(_ : KeyHandler.KeyKind, messageHash : Blob) : async* Result.Result<Blob, Text> {
      // Return a deterministic "signature" for testing
      let hash = Sha256.fromBlob(#sha256, messageHash);
      #ok(hash);
    };

    getPublicKey = func(_ : KeyHandler.KeyKind) : async* Result.Result<DID.Key.DID, Text> {
      // Return a mock public key
      let publicKeyBlob = Blob.fromArray(Array.concat([0x04 : Nat8], Array.repeat<Nat8>(0x01, 64))); // Uncompressed secp256k1 key
      let didKey : DID.Key.DID = {
        keyType = #secp256k1;
        publicKey = publicKeyBlob;
      };
      #ok(didKey);
    };
  };

  let serverInfoStableData : ServerInfoHandler.StableData = {
    hostname = "test.example.com";
    plcIdentifier = createTestDID();
    handlePrefix = null;
  };
  let serverInfoHandler = ServerInfoHandler.Handler(?serverInfoStableData);

  let tidGenerator = TID.Generator();

  (keyHandler, serverInfoHandler, tidGenerator);
};

await testAsync(
  "RepositoryHandler - Initialize Empty Repository",
  func() : async () {
    let (keyHandler, serverInfoHandler, tidGenerator) = createMockHandlers();

    let repositoryHandler = RepositoryHandler.Handler(
      null,
      keyHandler,
      serverInfoHandler,
      tidGenerator,
    );

    switch (await* repositoryHandler.initialize(null)) {
      case (#ok(())) {
        // Verify repository was created
        let repository = repositoryHandler.get();
        if (not repository.active) {
          Runtime.trap("Initialized repository should be active");
        };
      };
      case (#err(e)) Runtime.trap("Failed to initialize repository: " # e);
    };
  },
);

await testAsync(
  "RepositoryHandler - Create Record (like post method)",
  func() : async () {
    let (keyHandler, serverInfoHandler, tidGenerator) = createMockHandlers();

    let repositoryHandler = RepositoryHandler.Handler(
      null,
      keyHandler,
      serverInfoHandler,
      tidGenerator,
    );

    // Initialize repository first
    switch (await* repositoryHandler.initialize(null)) {
      case (#ok(())) {};
      case (#err(e)) Runtime.trap("Failed to initialize: " # e);
    };

    // Create a record like the post method does
    let now = DateTime.now();
    let createRecordRequest : RepositoryHandler.CreateRecordRequest = {
      collection = "app.bsky.feed.post";
      rkey = null; // Auto-generate
      record = #map([
        ("$type", #text("app.bsky.feed.post")),
        ("text", #text("Test message")),
        ("createdAt", #text(now.toTextFormatted(#iso))),
      ]);
      validate = null;
      swapCommit = null;
    };

    switch (await* repositoryHandler.createRecord(createRecordRequest)) {
      case (#ok(response)) {
        // Verify we got a CID back
        let cidText = CID.toText(response.cid);
        if (cidText == "") {
          Runtime.trap("Expected non-empty CID");
        };

        // Verify the rkey was auto-generated
        if (response.rkey == "") {
          Runtime.trap("Expected non-empty rkey");
        };

        // Verify commit metadata
        switch (response.commit) {
          case (?commit) {
            if (commit.cid == response.cid) {
              Runtime.trap("Commit CID should differ from record CID");
            };
          };
          case (null) Runtime.trap("Expected commit metadata");
        };
      };
      case (#err(e)) Runtime.trap("Failed to create record: " # e);
    };
  },
);

await testAsync(
  "RepositoryHandler - Create and Get Record",
  func() : async () {
    let (keyHandler, serverInfoHandler, tidGenerator) = createMockHandlers();

    let repositoryHandler = RepositoryHandler.Handler(
      null,
      keyHandler,
      serverInfoHandler,
      tidGenerator,
    );

    // Initialize repository
    switch (await* repositoryHandler.initialize(null)) {
      case (#ok(())) {};
      case (#err(e)) Runtime.trap("Failed to initialize: " # e);
    };

    // Create a record with a specific rkey
    let now = DateTime.now();
    let testRkey = "test-post-123";
    let createRecordRequest : RepositoryHandler.CreateRecordRequest = {
      collection = "app.bsky.feed.post";
      rkey = ?testRkey;
      record = #map([
        ("$type", #text("app.bsky.feed.post")),
        ("text", #text("Test message for retrieval")),
        ("createdAt", #text(now.toTextFormatted(#iso))),
      ]);
      validate = null;
      swapCommit = null;
    };

    let createdCID = switch (await* repositoryHandler.createRecord(createRecordRequest)) {
      case (#ok(response)) response.cid;
      case (#err(e)) Runtime.trap("Failed to create record: " # e);
    };

    // Now get the record back
    let getRequest : RepositoryHandler.GetRecordRequest = {
      collection = "app.bsky.feed.post";
      rkey = testRkey;
      cid = null;
    };

    switch (repositoryHandler.getRecord(getRequest)) {
      case (?response) {
        // Verify the CID matches
        if (response.cid != createdCID) {
          Runtime.trap("Retrieved CID doesn't match created CID");
        };

        // Verify the value
        switch (response.value) {
          case (#map(fields)) {
            var foundText = false;
            for ((key, value) in fields.vals()) {
              if (key == "text") {
                switch (value) {
                  case (#text(t)) {
                    if (t == "Test message for retrieval") {
                      foundText := true;
                    };
                  };
                  case (_) {};
                };
              };
            };
            if (not foundText) {
              Runtime.trap("Expected to find text field in record");
            };
          };
          case (_) Runtime.trap("Expected map value");
        };
      };
      case (null) Runtime.trap("Record not found after creation");
    };
  },
);

await testAsync(
  "RepositoryHandler - Create Multiple Records and List",
  func() : async () {
    let (keyHandler, serverInfoHandler, tidGenerator) = createMockHandlers();

    let repositoryHandler = RepositoryHandler.Handler(
      null,
      keyHandler,
      serverInfoHandler,
      tidGenerator,
    );

    // Initialize repository
    switch (await* repositoryHandler.initialize(null)) {
      case (#ok(())) {};
      case (#err(e)) Runtime.trap("Failed to initialize: " # e);
    };

    // Create multiple posts
    let messages = ["First post", "Second post", "Third post"];
    let now = DateTime.now();

    for (msg in messages.vals()) {
      let createRecordRequest : RepositoryHandler.CreateRecordRequest = {
        collection = "app.bsky.feed.post";
        rkey = null; // Auto-generate
        record = #map([
          ("$type", #text("app.bsky.feed.post")),
          ("text", #text(msg)),
          ("createdAt", #text(now.toTextFormatted(#iso))),
        ]);
        validate = null;
        swapCommit = null;
      };

      switch (await* repositoryHandler.createRecord(createRecordRequest)) {
        case (#ok(_)) {};
        case (#err(e)) Runtime.trap("Failed to create record: " # e);
      };
    };

    // List records
    let listRequest : RepositoryHandler.ListRecordsRequest = {
      collection = "app.bsky.feed.post";
      limit = null;
      cursor = null;
      rkeyStart = null;
      rkeyEnd = null;
      reverse = null;
    };

    let response = repositoryHandler.listRecords(listRequest);
    if (response.records.size() != messages.size()) {
      Runtime.trap("Expected " # debug_show (messages.size()) # " records, got " # debug_show (response.records.size()));
    };
  },
);

await testAsync(
  "RepositoryHandler - Create and Export Data",
  func() : async () {
    let (keyHandler, serverInfoHandler, tidGenerator) = createMockHandlers();

    let repositoryHandler = RepositoryHandler.Handler(
      null,
      keyHandler,
      serverInfoHandler,
      tidGenerator,
    );

    // Initialize repository
    switch (await* repositoryHandler.initialize(null)) {
      case (#ok(())) {};
      case (#err(e)) Runtime.trap("Failed to initialize: " # e);
    };

    // Create a record
    let now = DateTime.now();
    let createRecordRequest : RepositoryHandler.CreateRecordRequest = {
      collection = "app.bsky.feed.post";
      rkey = null;
      record = #map([
        ("$type", #text("app.bsky.feed.post")),
        ("text", #text("Test export")),
        ("createdAt", #text(now.toTextFormatted(#iso))),
      ]);
      validate = null;
      swapCommit = null;
    };

    switch (await* repositoryHandler.createRecord(createRecordRequest)) {
      case (#ok(_)) {};
      case (#err(e)) Runtime.trap("Failed to create record: " # e);
    };

    // Export repository data (like exportRepoData method)
    let repository = repositoryHandler.get();
    switch (Repository.exportData(repository, #full({ includeHistorical = true }))) {
      case (#ok(exportData)) {
        // Verify we have commits
        if (exportData.commits.size() == 0) {
          Runtime.trap("Expected at least one commit in export");
        };
        // Verify we have records
        if (exportData.records.size() == 0) {
          Runtime.trap("Expected at least one record in export");
        };
      };
      case (#err(e)) Runtime.trap("Failed to export data: " # e);
    };
  },
);

await testAsync(
  "RepositoryHandler - Get All Collections",
  func() : async () {
    let (keyHandler, serverInfoHandler, tidGenerator) = createMockHandlers();

    let repositoryHandler = RepositoryHandler.Handler(
      null,
      keyHandler,
      serverInfoHandler,
      tidGenerator,
    );

    // Initialize repository
    switch (await* repositoryHandler.initialize(null)) {
      case (#ok(())) {};
      case (#err(e)) Runtime.trap("Failed to initialize: " # e);
    };

    let now = DateTime.now();

    // Create records in different collections
    let collections = ["app.bsky.feed.post", "app.bsky.feed.like"];
    for (coll in collections.vals()) {
      let createRecordRequest : RepositoryHandler.CreateRecordRequest = {
        collection = coll;
        rkey = null;
        record = #map([
          ("$type", #text(coll)),
          ("createdAt", #text(now.toTextFormatted(#iso))),
        ]);
        validate = null;
        swapCommit = null;
      };

      switch (await* repositoryHandler.createRecord(createRecordRequest)) {
        case (#ok(_)) {};
        case (#err(e)) Runtime.trap("Failed to create record: " # e);
      };
    };

    // Get all collections
    let allCollections = repositoryHandler.getAllCollections();
    if (allCollections.size() != collections.size()) {
      Runtime.trap("Expected " # debug_show (collections.size()) # " collections, got " # debug_show (allCollections.size()));
    };
  },
);

await testAsync(
  "RepositoryHandler - Test State Persistence Pattern",
  func() : async () {
    let (keyHandler, serverInfoHandler, tidGenerator) = createMockHandlers();

    // Create handler without stable data
    let repositoryHandler = RepositoryHandler.Handler(
      null,
      keyHandler,
      serverInfoHandler,
      tidGenerator,
    );

    // Initialize
    switch (await* repositoryHandler.initialize(null)) {
      case (#ok(())) {};
      case (#err(e)) Runtime.trap("Failed to initialize: " # e);
    };

    // Create a record
    let now = DateTime.now();
    let createRecordRequest : RepositoryHandler.CreateRecordRequest = {
      collection = "app.bsky.feed.post";
      rkey = ?"test-123";
      record = #map([
        ("$type", #text("app.bsky.feed.post")),
        ("text", #text("Original post")),
        ("createdAt", #text(now.toTextFormatted(#iso))),
      ]);
      validate = null;
      swapCommit = null;
    };

    switch (await* repositoryHandler.createRecord(createRecordRequest)) {
      case (#ok(_)) {};
      case (#err(e)) Runtime.trap("Failed to create: " # e);
    };

    // Extract stable data (simulating preupgrade)
    let stableData = repositoryHandler.toStableData();

    // Create new handler from stable data (simulating postupgrade)
    let newRepositoryHandler = RepositoryHandler.Handler(
      stableData,
      keyHandler,
      serverInfoHandler,
      tidGenerator,
    );

    // Verify the record still exists in the new handler
    let getRequest : RepositoryHandler.GetRecordRequest = {
      collection = "app.bsky.feed.post";
      rkey = "test-123";
      cid = null;
    };

    switch (newRepositoryHandler.getRecord(getRequest)) {
      case (?_) {}; // Success - record found
      case (null) Runtime.trap("Record not found after simulating upgrade");
    };
  },
);
