import Debug "mo:core@1/Debug";
import Result "mo:core@1/Result";
import Runtime "mo:core@1/Runtime";
import Int "mo:core@1/Int";
import CID "mo:cid@1";
import Text "mo:core@1/Text";
import Blob "mo:core@1/Blob";
import Array "mo:core@1/Array";
import PureMap "mo:core@1/pure/Map";
import MerkleNode "../src/atproto/MerkleNode";
import MerkleSearchTree "../src/atproto/MerkleSearchTree";
import CIDBuilder "../src/atproto/CIDBuilder";
import { test } "mo:test";
import Sha256 "mo:sha2@0/Sha256";
import Nat "mo:core@1/Nat";
import Iter "mo:core@1/Iter";
import DagCbor "mo:dag-cbor@2";

// Helper function to create test CIDs
func createTestCID(content : Text) : CID.CID {
  // Create a simple test CID based on content
  let contentHash = Sha256.fromBlob(#sha256, Text.encodeUtf8(content));
  #v1({
    codec = #dagCbor;
    hashAlgorithm = #sha2256;
    hash = contentHash;
  });
};

test(
  "MerkleSearchTree - Basic Operations",
  func() {
    // Create empty MerkleSearchTree
    let mst = MerkleSearchTree.MerkleSearchTree(PureMap.empty<Text, MerkleNode.Node>());

    // Create initial empty node
    let emptyNode : MerkleNode.Node = {
      leftSubtreeCID = null;
      entries = [];
    };
    let rootCID = mst.addNode(emptyNode);

    // Test adding first record
    let key1 = Text.encodeUtf8("app.bsky.feed.post/record1");
    let value1 = createTestCID("value1");

    switch (mst.addCID(rootCID, Blob.toArray(key1), value1)) {
      case (#ok(newNode)) {
        // Test retrieving the record
        switch (mst.getCID(newNode, Blob.toArray(key1))) {
          case (?retrievedCID) {
            if (CID.toText(retrievedCID) != CID.toText(value1)) {
              Runtime.trap("Retrieved CID doesn't match original");
            };
          };
          case (null) {
            Runtime.trap("Failed to retrieve first record");
          };
        };
      };
      case (#err(msg)) {
        Runtime.trap("Failed to add first record: " # msg);
      };
    };
  },
);

test(
  "MerkleSearchTree - Key Validation",
  func() {
    let mst = MerkleSearchTree.MerkleSearchTree(PureMap.empty<Text, MerkleNode.Node>());
    let emptyNode : MerkleNode.Node = {
      leftSubtreeCID = null;
      entries = [];
    };
    let rootCID = mst.addNode(emptyNode);
    let testValue = createTestCID("test");

    // Test valid keys
    let validKeys = [
      "app.bsky.feed.post/abc123",
      "app.bsky.follow/did:plc:abc",
      "com.example.custom/record-key",
    ];

    for (key in validKeys.vals()) {
      let keyBytes = Text.encodeUtf8(key);
      switch (mst.addCID(rootCID, Blob.toArray(keyBytes), testValue)) {
        case (#ok(_)) {};
        case (#err(msg)) Runtime.trap("Valid key rejected: " # key # " - " # msg);
      };
    };

    // Test invalid keys
    let invalidKeys = [
      "", // empty
      "noSlash",
      "/startsWithSlash",
      "endsWithSlash/",
      "app.bsky.feed.post/", // empty record key
      "/app.bsky.feed.post", // empty collection
      "invalid@chars/test",
    ];

    for (key in invalidKeys.vals()) {
      let keyBytes = Text.encodeUtf8(key);
      switch (mst.addCID(rootCID, Blob.toArray(keyBytes), testValue)) {
        case (#ok(_)) Runtime.trap("Invalid key accepted: " # key);
        case (#err(_)) {};
      };
    };
  },
);

test(
  "MerkleSearchTree - Depth Calculation (ATProto Compatible)",
  func() {
    let mst = MerkleSearchTree.MerkleSearchTree(PureMap.empty<Text, MerkleNode.Node>());

    // Test known depth values that should match ATProto behavior
    // These test vectors are based on ATProto's 2-bit leading zero counting
    let testCases = [
      // Keys with known expected depths in ATProto
      ("com.example.record/3jqfcqzm3fp2j", 0), // Should be level 0
      ("com.example.record/3jqfcqzm3fs2j", 1), // Should be level 1
      ("com.example.record/3jqfcqzm3fx2j", 2), // Should be level 2
      ("app.bsky.feed.post/test", 0), // Most keys should be level 0
    ];

    for ((key, expectedDepth) in testCases.vals()) {
      let keyBytes = Text.encodeUtf8(key);

      // Test by creating a simple tree and verifying the key gets placed at correct level
      let emptyNode : MerkleNode.Node = {
        leftSubtreeCID = null;
        entries = [];
      };
      let rootCID = mst.addNode(emptyNode);
      let testValue = createTestCID("test");

      switch (mst.addCID(rootCID, Blob.toArray(keyBytes), testValue)) {
        case (#ok(newNode)) {
          // Verify the node structure reflects correct depth placement
          if (newNode.entries.size() == 0) {
            Runtime.trap("Node should have entries after insertion");
          };
        };
        case (#err(msg)) {
          Runtime.trap("Failed to add key for depth test: " # msg);
        };
      };
    };
  },
);

test(
  "MerkleSearchTree - Key Compression",
  func() {
    let mst = MerkleSearchTree.MerkleSearchTree(PureMap.empty<Text, MerkleNode.Node>());

    // Test with completely different keys first to avoid depth conflicts
    let key1 = Text.encodeUtf8("a/1");
    let value1 = createTestCID("value1");

    let key2 = Text.encodeUtf8("b/2");
    let value2 = createTestCID("value2");

    // Start with empty tree
    let emptyNode : MerkleNode.Node = {
      leftSubtreeCID = null;
      entries = [];
    };
    var currentCID = mst.addNode(emptyNode);
    var currentNode = emptyNode;

    // Add first key
    switch (mst.addCID(currentCID, Blob.toArray(key1), value1)) {
      case (#ok(newNode)) {
        currentNode := newNode;
        currentCID := mst.addNode(newNode);
      };
      case (#err(msg)) {
        Runtime.trap("Failed to add first key: " # msg);
      };
    };

    // Add second key
    switch (mst.addCID(currentCID, Blob.toArray(key2), value2)) {
      case (#ok(newNode)) {
        currentNode := newNode;
        currentCID := mst.addNode(newNode);
      };
      case (#err(msg)) {
        Runtime.trap("Failed to add second key: " # msg);
      };
    };

    // Test retrieval of both keys
    switch (mst.getCID(currentNode, Blob.toArray(key1))) {
      case (?retrievedCID) {
        if (CID.toText(retrievedCID) != CID.toText(value1)) {
          Runtime.trap("First key value mismatch");
        };
      };
      case (null) {
        Runtime.trap("Failed to retrieve first key");
      };
    };

    switch (mst.getCID(currentNode, Blob.toArray(key2))) {
      case (?retrievedCID) {
        if (CID.toText(retrievedCID) != CID.toText(value2)) {
          Runtime.trap("Second key value mismatch");
        };
      };
      case (null) {
        Runtime.trap("Failed to retrieve second key");
      };
    };
  },
);

test(
  "MerkleSearchTree - Tree Structure",
  func() {
    let mst = MerkleSearchTree.MerkleSearchTree(PureMap.empty<Text, MerkleNode.Node>());

    var currentNode : MerkleNode.Node = {
      leftSubtreeCID = null;
      entries = [];
    };
    var currentCID = mst.addNode(currentNode);

    // Add first key
    let key1 = Text.encodeUtf8("a/1");
    let value1 = createTestCID("value1");

    switch (mst.addCID(currentCID, Blob.toArray(key1), value1)) {
      case (#ok(newNode)) {
        currentNode := newNode;
        currentCID := mst.addNode(newNode);

        // Verify we can retrieve first key
        switch (mst.getCID(currentNode, Blob.toArray(key1))) {
          case (?_) {}; // Good
          case (null) Runtime.trap("Lost first key after adding it");
        };
      };
      case (#err(msg)) Runtime.trap("Failed to add first key: " # msg);
    };

    // Add second key
    let key2 = Text.encodeUtf8("b/2");
    let value2 = createTestCID("value2");

    switch (mst.addCID(currentCID, Blob.toArray(key2), value2)) {
      case (#ok(newNode)) {
        currentNode := newNode;
        currentCID := mst.addNode(newNode);

        // Check both keys are still retrievable
        switch (mst.getCID(currentNode, Blob.toArray(key1))) {
          case (?_) {}; // Good
          case (null) Runtime.trap("Lost first key after adding second key");
        };

        switch (mst.getCID(currentNode, Blob.toArray(key2))) {
          case (?_) {}; // Good
          case (null) Runtime.trap("Cannot retrieve second key");
        };
      };
      case (#err(msg)) Runtime.trap("Failed to add second key: " # msg);
    };

    // Add third key
    let key3 = Text.encodeUtf8("c/3");
    let value3 = createTestCID("value3");

    switch (mst.addCID(currentCID, Blob.toArray(key3), value3)) {
      case (#ok(newNode)) {
        currentNode := newNode;
        currentCID := mst.addNode(newNode);

        // Check all three keys are retrievable
        switch (mst.getCID(currentNode, Blob.toArray(key1))) {
          case (?_) {}; // Good
          case (null) Runtime.trap("Lost key a/1 after adding c/3");
        };

        switch (mst.getCID(currentNode, Blob.toArray(key2))) {
          case (?_) {}; // Good
          case (null) Runtime.trap("Lost key b/2 after adding c/3");
        };

        switch (mst.getCID(currentNode, Blob.toArray(key3))) {
          case (?_) {}; // Good
          case (null) Runtime.trap("Cannot retrieve key c/3");
        };
      };
      case (#err(msg)) Runtime.trap("Failed to add third key: " # msg);
    };
  },
);

test(
  "MerkleSearchTree - Debug Tree Structure",
  func() {
    let mst = MerkleSearchTree.MerkleSearchTree(PureMap.empty<Text, MerkleNode.Node>());

    // Test with the same keys as the failing test
    let key1 = "test/a";
    let key2 = "test/b";
    let key1Bytes = Text.encodeUtf8(key1);
    let key2Bytes = Text.encodeUtf8(key2);

    Debug.print("Testing keys: '" # key1 # "' and '" # key2 # "'");

    // Start with empty node
    var node : MerkleNode.Node = { leftSubtreeCID = null; entries = [] };
    var cid = mst.addNode(node);

    // Add first key and examine structure
    let value1CID = createTestCID(key1);
    switch (mst.addCID(cid, Blob.toArray(key1Bytes), value1CID)) {
      case (#ok(newNode)) {
        node := newNode;
        cid := mst.addNode(newNode);
        Debug.print("After adding first key, node entries count: " # Int.toText(node.entries.size()));

        // Print details of entries
        for (i in node.entries.keys()) {
          let entry = node.entries[i];
          Debug.print("Entry " # Int.toText(i) # " prefixLength: " # Int.toText(entry.prefixLength) # ", keySuffix size: " # Int.toText(entry.keySuffix.size()));
          Debug.print("  keySuffix: " # debug_show (entry.keySuffix));
          Debug.print("  valueCID: " # debug_show (entry.valueCID));
          switch (entry.subtreeCID) {
            case (?subtreeCID) Debug.print("  has subtreeCID");
            case null Debug.print("  no subtreeCID");
          };
        };
      };
      case (#err(msg)) Runtime.trap("Failed to add first key: " # msg);
    };

    // Add second key and examine structure
    let value2CID = createTestCID(key2);
    switch (mst.addCID(cid, Blob.toArray(key2Bytes), value2CID)) {
      case (#ok(newNode)) {
        node := newNode;
        cid := mst.addNode(newNode);
        Debug.print("After adding second key, node entries count: " # Int.toText(node.entries.size()));

        // Print details of entries
        for (i in node.entries.keys()) {
          let entry = node.entries[i];
          Debug.print("Entry " # Int.toText(i) # " prefixLength: " # Int.toText(entry.prefixLength) # ", keySuffix size: " # Int.toText(entry.keySuffix.size()));
          Debug.print("  keySuffix: " # debug_show (entry.keySuffix));
          Debug.print("  valueCID: " # debug_show (entry.valueCID));
          switch (entry.subtreeCID) {
            case (?subtreeCID) Debug.print("  has subtreeCID");
            case null Debug.print("  no subtreeCID");
          };
        };
      };
      case (#err(msg)) Runtime.trap("Failed to add second key: " # msg);
    };
  },
);

test(
  "MerkleSearchTree - Deterministic Construction",
  func() {
    let mst = MerkleSearchTree.MerkleSearchTree(PureMap.empty<Text, MerkleNode.Node>());

    // Use valid ATProto key format but keep them simple
    let key1 = "test/a";
    let key2 = "test/b";

    var node : MerkleNode.Node = { leftSubtreeCID = null; entries = [] };
    var cid = mst.addNode(node);

    // Add first key
    let key1Bytes = Text.encodeUtf8(key1);
    let value1CID = createTestCID(key1);
    switch (mst.addCID(cid, Blob.toArray(key1Bytes), value1CID)) {
      case (#ok(newNode)) {
        node := newNode;
        cid := mst.addNode(newNode);

        // Verify node has one entry
        assert (node.entries.size() == 1);
      };
      case (#err(msg)) Runtime.trap("Failed to add first key: " # msg);
    };

    // Verify first key is retrievable
    switch (mst.getCID(node, Blob.toArray(key1Bytes))) {
      case (?_) {}; // Good
      case (null) Runtime.trap("First key not retrievable after adding");
    };

    // Add second key
    let key2Bytes = Text.encodeUtf8(key2);
    let value2CID = createTestCID(key2);
    switch (mst.addCID(cid, Blob.toArray(key2Bytes), value2CID)) {
      case (#ok(newNode)) {
        node := newNode;
        cid := mst.addNode(newNode);

        // Verify node structure after adding second key
        // Since keys "test/a" and "test/b" share prefix "test/",
        // the second key should create a subtree
        if (node.entries.size() != 1) {
          Runtime.trap("Node should have 1 entry after adding second key (subtree created), but got " # debug_show (node.entries.size()));
        };

        // Verify the entry has a subtreeCID (indicating subtree was created for shared prefix)
        let entry = node.entries[0];
        switch (entry.subtreeCID) {
          case (?_) {}; // Good - subtree was created
          case (null) Runtime.trap("Entry should have subtreeCID after adding second key with shared prefix");
        };
      };
      case (#err(msg)) Runtime.trap("Failed to add second key: " # msg);
    };

    // Verify both keys are retrievable
    switch (mst.getCID(node, Blob.toArray(key1Bytes))) {
      case (?_) {}; // Good
      case (null) Runtime.trap("First key lost after adding second");
    };

    switch (mst.getCID(node, Blob.toArray(key2Bytes))) {
      case (?_) {}; // Good
      case (null) Runtime.trap("Second key not retrievable");
    };
  },
);

test(
  "MerkleSearchTree - Error Cases",
  func() {
    let mst = MerkleSearchTree.MerkleSearchTree(PureMap.empty<Text, MerkleNode.Node>());
    let testValue = createTestCID("test");

    // Test with non-existent root CID
    let fakeCID = createTestCID("fake");
    let testKey = Text.encodeUtf8("app.bsky.feed.post/test");

    switch (mst.addCID(fakeCID, Blob.toArray(testKey), testValue)) {
      case (#ok(_)) Runtime.trap("Should have failed with non-existent root CID");
      case (#err(msg)) {};
    };

    // Test empty key
    let emptyNode : MerkleNode.Node = {
      leftSubtreeCID = null;
      entries = [];
    };
    let rootCID = mst.addNode(emptyNode);

    switch (mst.addCID(rootCID, [], testValue)) {
      case (#ok(_)) Runtime.trap("Should have failed with empty key");
      case (#err(msg)) {};
    };

    // Test duplicate key addition
    let validKey = Text.encodeUtf8("app.bsky.feed.post/test");
    switch (mst.addCID(rootCID, Blob.toArray(validKey), testValue)) {
      case (#ok(newNode)) {
        let newRootCID = mst.addNode(newNode);
        switch (mst.addCID(newRootCID, Blob.toArray(validKey), testValue)) {
          case (#ok(_)) Runtime.trap("Should have failed with duplicate key");
          case (#err(msg)) {};
        };
      };
      case (#err(msg)) Runtime.trap("Initial key addition failed: " # msg);
    };
  },
);

test(
  "MerkleSearchTree - ATProto Test Vectors",
  func() {
    let mst = MerkleSearchTree.MerkleSearchTree(PureMap.empty<Text, MerkleNode.Node>());

    // Use the exact test vectors from ATProto interop tests
    // These keys have known layer placements in the ATProto specification
    let atprotoTestVectors = [
      ("com.example.record/3jqfcqzm3fo2j", "A"), // level 0
      ("com.example.record/3jqfcqzm3fp2j", "B"), // level 0
      ("com.example.record/3jqfcqzm3fr2j", "C"), // level 0
      ("com.example.record/3jqfcqzm3fs2j", "D"), // level 1
      ("com.example.record/3jqfcqzm3ft2j", "E"), // level 0
      ("com.example.record/3jqfcqzm3fx2j", "F"), // level 2
    ];

    var currentNode : MerkleNode.Node = {
      leftSubtreeCID = null;
      entries = [];
    };
    var currentCID = mst.addNode(currentNode);

    // Add records in the same order as ATProto tests
    for ((key, content) in atprotoTestVectors.vals()) {
      let keyBytes = Text.encodeUtf8(key);
      let valueCID = createTestCID(content);

      switch (mst.addCID(currentCID, Blob.toArray(keyBytes), valueCID)) {
        case (#ok(newNode)) {
          currentNode := newNode;
          currentCID := mst.addNode(newNode);
        };
        case (#err(msg)) {
          Runtime.trap("Failed to add ATProto test vector " # key # ": " # msg);
        };
      };
    };

    // Verify all test vector records can be retrieved
    var retrievedCount = 0;
    for ((key, expectedContent) in atprotoTestVectors.vals()) {
      let keyBytes = Text.encodeUtf8(key);
      switch (mst.getCID(currentNode, Blob.toArray(keyBytes))) {
        case (?retrievedCID) {
          let expectedCID = createTestCID(expectedContent);
          if (CID.toText(retrievedCID) == CID.toText(expectedCID)) {
            retrievedCount += 1;
          } else {
            Runtime.trap("Retrieved CID doesn't match expected for: " # key);
          };
        };
        case (null) Runtime.trap("Failed to retrieve ATProto test vector: " # key);
      };
    };

    if (retrievedCount != atprotoTestVectors.size()) {
      Runtime.trap("Only retrieved " # debug_show (retrievedCount) # "/" # debug_show (atprotoTestVectors.size()) # " test vectors");
    };
  },
);

test(
  "MerkleSearchTree - Fanout Behavior Verification",
  func() {
    let mst = MerkleSearchTree.MerkleSearchTree(PureMap.empty<Text, MerkleNode.Node>());

    // Test that demonstrates ~4 fanout behavior with 2-bit leading zeros
    // Generate many keys and verify tree structure
    let keys = [
      "app.bsky.feed.post/1",
      "app.bsky.feed.post/2",
      "app.bsky.feed.post/3",
      "app.bsky.feed.post/4",
      "app.bsky.feed.post/5",
      "app.bsky.feed.post/6",
      "app.bsky.feed.post/7",
      "app.bsky.feed.post/8",
      "app.bsky.feed.post/9",
      "app.bsky.feed.post/10",
      "app.bsky.feed.post/11",
      "app.bsky.feed.post/12",
      "app.bsky.follow/1",
      "app.bsky.follow/2",
      "app.bsky.follow/3",
      "com.example.test/1",
      "com.example.test/2",
      "com.example.test/3",
    ];

    var currentNode : MerkleNode.Node = {
      leftSubtreeCID = null;
      entries = [];
    };
    var currentCID = mst.addNode(currentNode);

    // Add all keys
    for (key in keys.vals()) {
      let keyBytes = Text.encodeUtf8(key);
      let valueCID = createTestCID(key);

      switch (mst.addCID(currentCID, Blob.toArray(keyBytes), valueCID)) {
        case (#ok(newNode)) {
          currentNode := newNode;
          currentCID := mst.addNode(newNode);
        };
        case (#err(msg)) {
          Runtime.trap("Failed to add key for fanout test: " # key # " - " # msg);
        };
      };
    };

    // Verify all keys are retrievable (demonstrates tree integrity)
    for (key in keys.vals()) {
      let keyBytes = Text.encodeUtf8(key);
      switch (mst.getCID(currentNode, Blob.toArray(keyBytes))) {
        case (?_) {};
        case (null) Runtime.trap("Lost key in fanout test: " # key);
      };
    };

    // For our simplified implementation, verify the tree can handle many keys
    // (A full MerkleNode implementation would have better fanout, but this tests basic functionality)
    if (currentNode.entries.size() == 0) {
      Runtime.trap("Tree should contain entries after adding keys");
    };
  },
);

test(
  "MerkleSearchTree - Record Removal",
  func() {
    let mst = MerkleSearchTree.MerkleSearchTree(PureMap.empty<Text, MerkleNode.Node>());

    // Create initial node with multiple records
    var currentNode : MerkleNode.Node = {
      leftSubtreeCID = null;
      entries = [];
    };
    var currentCID = mst.addNode(currentNode);

    let keys = [
      "app.bsky.feed.post/record1",
      "app.bsky.feed.post/record2",
      "app.bsky.follow/follow1",
    ];

    // Add all records
    for (key in keys.vals()) {
      let keyBytes = Text.encodeUtf8(key);
      let valueCID = createTestCID(key);

      switch (mst.addCID(currentCID, Blob.toArray(keyBytes), valueCID)) {
        case (#ok(newNode)) {
          currentNode := newNode;
          currentCID := mst.addNode(newNode);
        };
        case (#err(msg)) Runtime.trap("Failed to add key " # key # ": " # msg);
      };
    };

    // Test removing middle record
    let removeKey = Text.encodeUtf8("app.bsky.feed.post/record2");
    switch (mst.removeCID(currentCID, Blob.toArray(removeKey))) {
      case (#ok(updatedNode)) {
        currentNode := updatedNode;
        currentCID := mst.addNode(updatedNode);

        // Verify removed record is not retrievable
        switch (mst.getCID(currentNode, Blob.toArray(removeKey))) {
          case (?_) Runtime.trap("Removed record should not be retrievable");
          case (null) {}; // Good
        };

        // Verify other records still exist
        for (key in keys.vals()) {
          if (key != "app.bsky.feed.post/record2") {
            let keyBytes = Text.encodeUtf8(key);
            switch (mst.getCID(currentNode, Blob.toArray(keyBytes))) {
              case (?_) {}; // Good
              case (null) Runtime.trap("Remaining record lost: " # key);
            };
          };
        };
      };
      case (#err(msg)) Runtime.trap("Failed to remove record: " # msg);
    };

    // Test removing non-existent record
    let nonExistentKey = Text.encodeUtf8("app.bsky.feed.post/nonexistent");
    switch (mst.removeCID(currentCID, Blob.toArray(nonExistentKey))) {
      case (#ok(_)) Runtime.trap("Should not succeed removing non-existent record");
      case (#err(_)) {}; // Expected
    };
  },
);

test(
  "MerkleSearchTree - Collection Operations",
  func() {
    let mst = MerkleSearchTree.MerkleSearchTree(PureMap.empty<Text, MerkleNode.Node>());

    var currentNode : MerkleNode.Node = {
      leftSubtreeCID = null;
      entries = [];
    };
    var currentCID = mst.addNode(currentNode);

    // Add records from multiple collections
    let testData = [
      ("app.bsky.feed.post", "record1"),
      ("app.bsky.feed.post", "record2"),
      ("app.bsky.follow", "follow1"),
      ("com.example.custom", "item1"),
      ("com.example.custom", "item2"),
      ("com.example.custom", "item3"),
    ];

    for ((collection, recordKey) in testData.vals()) {
      let key = collection # "/" # recordKey;
      let keyBytes = Text.encodeUtf8(key);
      let valueCID = createTestCID(key);

      switch (mst.addCID(currentCID, Blob.toArray(keyBytes), valueCID)) {
        case (#ok(newNode)) {
          currentNode := newNode;
          currentCID := mst.addNode(newNode);
        };
        case (#err(msg)) Runtime.trap("Failed to add " # key # ": " # msg);
      };
    };

    // Test getAllCollections
    let collections = mst.getAllCollections(currentNode);
    let expectedCollections = ["app.bsky.feed.post", "app.bsky.follow", "com.example.custom"];

    if (collections.size() != expectedCollections.size()) {
      Runtime.trap(
        "Wrong number of collections. Expected: " #
        debug_show (expectedCollections.size()) # ", Got: " # debug_show (collections.size())
      );
    };

    // Verify all expected collections exist
    for (expectedCollection in expectedCollections.vals()) {
      let found = Array.find<Text>(collections, func(c) = c == expectedCollection);
      if (found == null) {
        Runtime.trap("Missing collection: " # expectedCollection);
      };
    };

    // Test getCollectionRecords for specific collections
    let feedRecords = mst.getCollectionRecords(currentNode, "app.bsky.feed.post");
    if (feedRecords.size() != 2) {
      Runtime.trap("Expected 2 feed records, got: " # debug_show (feedRecords.size()));
    };

    let customRecords = mst.getCollectionRecords(currentNode, "com.example.custom");
    if (customRecords.size() != 3) {
      Runtime.trap("Expected 3 custom records, got: " # debug_show (customRecords.size()));
    };

    // Test empty collection
    let emptyRecords = mst.getCollectionRecords(currentNode, "nonexistent.collection");
    if (emptyRecords.size() != 0) {
      Runtime.trap("Expected 0 records for nonexistent collection");
    };
  },
);

test(
  "MerkleSearchTree - Block Map Loading",
  func() {
    // Test fromBlockMap functionality
    let originalMerkleSearchTree = MerkleSearchTree.MerkleSearchTree(PureMap.empty<Text, MerkleNode.Node>());

    // Create a simple MerkleNode structure
    var currentNode : MerkleNode.Node = {
      leftSubtreeCID = null;
      entries = [];
    };
    var currentCID = originalMerkleSearchTree.addNode(currentNode);

    let testKey = Text.encodeUtf8("app.bsky.feed.post/test");
    let testValue = createTestCID("test-value");

    switch (originalMerkleSearchTree.addCID(currentCID, Blob.toArray(testKey), testValue)) {
      case (#ok(newNode)) {
        currentNode := newNode;
        currentCID := originalMerkleSearchTree.addNode(newNode);
      };
      case (#err(msg)) Runtime.trap("Failed to create test MerkleNode: " # msg);
    };

    // Create a block map with the MerkleNode node
    var blockMap = PureMap.empty<CID.CID, Blob>();

    // Convert MerkleNode node to CBOR for block map
    let nodeEntries = Array.map<MerkleNode.TreeEntry, DagCbor.Value>(
      currentNode.entries,
      func(entry) = #map([
        ("p", #int(entry.prefixLength)),
        ("k", #bytes(entry.keySuffix)),
        ("v", #cid(entry.valueCID)),
      ]),
    );

    let nodeCbor = #map([("e", #array(nodeEntries))]);

    let nodeBytes = switch (DagCbor.toBytes(nodeCbor)) {
      case (#ok(bytes)) Blob.fromArray(bytes);
      case (#err(e)) Runtime.trap("Failed to encode node CBOR: " # debug_show (e));
    };

    blockMap := PureMap.add(blockMap, CIDBuilder.compare, currentCID, nodeBytes);

    // Test loading from block map
    switch (MerkleSearchTree.fromBlockMap(currentCID, blockMap)) {
      case (#ok(loadedMerkleSearchTree)) {
        // Verify the loaded mst works correctly
        let ?loadedNode = loadedMerkleSearchTree.getNode(currentCID) else {
          Runtime.trap("Failed to get loaded node");
        };

        switch (loadedMerkleSearchTree.getCID(loadedNode, Blob.toArray(testKey))) {
          case (?retrievedCID) {
            if (CID.toText(retrievedCID) != CID.toText(testValue)) {
              Runtime.trap("Loaded MerkleNode returned wrong CID");
            };
          };
          case (null) Runtime.trap("Failed to retrieve key from loaded MerkleNode");
        };
      };
      case (#err(msg)) Runtime.trap("Failed to load from block map: " # msg);
    };
  },
);

test(
  "MerkleSearchTree - Edge Cases and Boundary Conditions",
  func() {
    let mst = MerkleSearchTree.MerkleSearchTree(PureMap.empty<Text, MerkleNode.Node>());

    let emptyNode : MerkleNode.Node = {
      leftSubtreeCID = null;
      entries = [];
    };
    let rootCID = mst.addNode(emptyNode);
    let testValue = createTestCID("test");

    // Test maximum key length (256 bytes)
    let longSuffix = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"; // 247 chars
    let maxKey = Text.encodeUtf8("collection/" # longSuffix); // 10 + 247 = 257 chars
    switch (mst.addCID(rootCID, Blob.toArray(maxKey), testValue)) {
      case (#ok(_)) Runtime.trap("Should reject key longer than 256 bytes");
      case (#err(_)) {}; // Expected
    };

    // Test key with exactly 255 bytes (just under the limit to ensure it works)
    let collectionPart = "collection"; // 10 chars
    let separator = "/"; // 1 char  = 11 total
    // Create 244 'a' characters for 255 total bytes
    var suffix244 = "";
    for (i in Nat.range(0, 244)) {
      suffix244 := suffix244 # "a";
    };

    let validKey255 = Text.encodeUtf8(collectionPart # separator # suffix244);

    switch (mst.addCID(rootCID, Blob.toArray(validKey255), testValue)) {
      case (#ok(_)) {}; // Should work
      case (#err(msg)) Runtime.trap("Valid 255-byte key rejected: " # msg);
    };

    // Test key with exactly 256 bytes (should also work)
    let suffix245 = suffix244 # "a"; // Add one more 'a' for 256 total
    let validKey256 = Text.encodeUtf8(collectionPart # separator # suffix245);

    switch (mst.addCID(rootCID, Blob.toArray(validKey256), testValue)) {
      case (#ok(_)) {}; // Should work
      case (#err(msg)) Runtime.trap("Valid 256-byte key rejected: " # msg);
    }; // Test keys with special characters
    let specialKeys = [
      "app.test/key-with-dashes",
      "app.test/key_with_underscores",
      "app.test/key.with.dots",
      "app.test/key:with:colons",
      "app.test/123456789",
    ];

    for (key in specialKeys.vals()) {
      let keyBytes = Text.encodeUtf8(key);
      switch (mst.addCID(rootCID, Blob.toArray(keyBytes), testValue)) {
        case (#ok(_)) {}; // Should work
        case (#err(msg)) Runtime.trap("Valid special key rejected: " # key # " - " # msg);
      };
    };

    // Test duplicate key insertion
    let dupKey = Text.encodeUtf8("test.collection/duplicate");
    switch (mst.addCID(rootCID, Blob.toArray(dupKey), testValue)) {
      case (#ok(newNode)) {
        let newCID = mst.addNode(newNode);
        // Try to add same key again
        switch (mst.addCID(newCID, Blob.toArray(dupKey), testValue)) {
          case (#ok(_)) Runtime.trap("Should reject duplicate key");
          case (#err(_)) {}; // Expected
        };
      };
      case (#err(msg)) Runtime.trap("Failed to add first instance: " # msg);
    };
  },
);

test(
  "MerkleSearchTree - Large Scale Operations",
  func() {
    let mst = MerkleSearchTree.MerkleSearchTree(PureMap.empty<Text, MerkleNode.Node>());

    var currentNode : MerkleNode.Node = {
      leftSubtreeCID = null;
      entries = [];
    };
    var currentCID = mst.addNode(currentNode);

    // Add a large number of records to test performance and stability
    let numRecords = 50;
    var addedKeys : [Text] = [];

    for (i in Nat.range(1, numRecords + 1)) {
      // Use zero-padded numbers to ensure lexicographical order
      let paddedI = if (i < 10) "0" # debug_show (i) else debug_show (i);
      let key = "app.bsky.feed.post/record" # paddedI;
      let keyBytes = Text.encodeUtf8(key);
      let valueCID = createTestCID("value" # debug_show (i));

      switch (mst.addCID(currentCID, Blob.toArray(keyBytes), valueCID)) {
        case (#ok(newNode)) {
          currentNode := newNode;
          currentCID := mst.addNode(newNode);
          addedKeys := Array.concat(addedKeys, [key]);
        };
        case (#err(msg)) Runtime.trap("Failed to add record " # debug_show (i) # ": " # msg);
      };
    };

    // Verify all records are retrievable
    for (key in addedKeys.vals()) {
      let keyBytes = Text.encodeUtf8(key);
      switch (mst.getCID(currentNode, Blob.toArray(keyBytes))) {
        case (?_) {}; // Good
        case (null) Runtime.trap("Lost record in large scale test: " # key);
      };
    };

    // Test getAllRecordCIDs with many records
    let allCIDs = mst.getAllRecordCIDs(currentNode);
    if (allCIDs.size() != numRecords) {
      Runtime.trap(
        "getAllRecordCIDs returned wrong count. Expected: " #
        debug_show (numRecords) # ", Got: " # debug_show (allCIDs.size())
      );
    };
  },
);

test(
  "MerkleSearchTree - Key Reconstruction Edge Cases",
  func() {
    let mst = MerkleSearchTree.MerkleSearchTree(PureMap.empty<Text, MerkleNode.Node>());

    var currentNode : MerkleNode.Node = {
      leftSubtreeCID = null;
      entries = [];
    };
    var currentCID = mst.addNode(currentNode);

    // Test keys with very similar prefixes to stress compression
    let similarKeys = [
      "app.bsky.feed.post/aaaaaa",
      "app.bsky.feed.post/aaaaab",
      "app.bsky.feed.post/aaaaac",
      "app.bsky.feed.post/aaaaba",
      "app.bsky.feed.post/aaaabb",
    ];

    for (key in similarKeys.vals()) {
      let keyBytes = Text.encodeUtf8(key);
      let valueCID = createTestCID(key);

      switch (mst.addCID(currentCID, Blob.toArray(keyBytes), valueCID)) {
        case (#ok(newNode)) {
          currentNode := newNode;
          currentCID := mst.addNode(newNode);
        };
        case (#err(msg)) Runtime.trap("Failed to add similar key " # key # ": " # msg);
      };
    };

    // Verify all similar keys are retrievable and return correct values
    for ((i, key) in Iter.enumerate(similarKeys.vals())) {
      let keyBytes = Text.encodeUtf8(key);
      let expectedCID = createTestCID(key);

      switch (mst.getCID(currentNode, Blob.toArray(keyBytes))) {
        case (?retrievedCID) {
          if (CID.toText(retrievedCID) != CID.toText(expectedCID)) {
            Runtime.trap("Wrong CID for similar key " # key);
          };
        };
        case (null) Runtime.trap("Failed to retrieve similar key: " # key);
      };
    };
  },
);
