import Bench "mo:bench";
import Nat "mo:core@1/Nat";
import Result "mo:core@1/Result";
import Blob "mo:core@1/Blob";
import Runtime "mo:core@1/Runtime";
import CID "mo:cid@1";
import MerkleSearchTree "../src/MerkleSearchTree";
import Array "mo:core@1/Array";

module {

  public func init() : Bench.Bench {
    // Test data
    let testKeys = [
      "app.bsky.feed.post/3k2yihcrp2c2a",
      "app.bsky.feed.post/3k2yihcrp2c2b",
      "app.bsky.feed.post/3k2yihcrp2c2c",
      "app.bsky.feed.like/3k2yihcrp2c2d",
      "app.bsky.graph.follow/3k2yihcrp2c2e",
    ];

    // Pre-generate test CIDs
    let testCID1 = switch (CID.fromText("bafyreihyrpefhacm6kkp4ql6j6udakdit7g3dmkzfriqfykhjw6cad7lrm")) {
      case (#ok(cid)) cid;
      case (#err(e)) Runtime.trap("Failed to parse CID: " # e);
    };

    let testCID2 = switch (CID.fromText("bafyreidj5idub6mapiupjwjsyyxhyhedxycv4vihfsicm2vt46o7morwlm")) {
      case (#ok(cid)) cid;
      case (#err(e)) Runtime.trap("Failed to parse CID: " # e);
    };

    // Pre-populate MerkleSearchTrees
    var populatedMerkleSearchTree = MerkleSearchTree.empty();
    for (i in testKeys.keys()) {
      let cid = if (i % 2 == 0) testCID1 else testCID2;
      populatedMerkleSearchTree := switch (MerkleSearchTree.add(populatedMerkleSearchTree, testKeys[i], cid)) {
        case (#ok(mst)) mst;
        case (#err(e)) Runtime.trap("Failed to populate MerkleSearchTree: " # e);
      };
    };

    let bench = Bench.Bench();

    bench.name("MerkleSearchTree Operations Benchmarks");
    bench.description("Benchmark core MerkleSearchTree operations: add, get, remove, validate");

    bench.rows([
      "add_single",
      "get_exists",
      "get_missing",
      "remove_exists",
      "remove_missing",
      "validate",
      "size",
    ]);

    bench.cols(["1", "10", "100"]);
    var mst = MerkleSearchTree.empty();

    bench.runner(
      func(row, col) {
        let ?n = Nat.fromText(col) else Runtime.trap("Cols must only contain numbers: " # col);

        let operation = switch (row) {
          case ("add_single") func(i : Nat) : Result.Result<Any, Text> {
            let key = testKeys[i % testKeys.size()];
            let cid = if (i % 2 == 0) testCID1 else testCID2;
            switch (MerkleSearchTree.add(mst, key, cid)) {
              case (#ok(_)) #ok;
              case (#err(e)) #err(e);
            };
          };

          case ("get_exists") func(i : Nat) : Result.Result<Any, Text> {
            let key = testKeys[i % testKeys.size()];
            switch (MerkleSearchTree.get(populatedMerkleSearchTree, key)) {
              case (?_) #ok;
              case (null) #err("Key not found");
            };
          };

          case ("get_missing") func(i : Nat) : Result.Result<Any, Text> {
            switch (MerkleSearchTree.get(populatedMerkleSearchTree, "app.bsky.feed.post/nonexistent" # Nat.toText(i))) {
              case (null) #ok;
              case (?_) #err("Found unexpected key");
            };
          };

          case ("remove_exists") func(i : Nat) : Result.Result<Any, Text> {
            let key = testKeys[i % testKeys.size()];
            switch (MerkleSearchTree.remove(populatedMerkleSearchTree, key)) {
              case (#ok(_)) #ok;
              case (#err(e)) #err(e);
            };
          };

          case ("remove_missing") func(i : Nat) : Result.Result<Any, Text> {
            switch (MerkleSearchTree.remove(populatedMerkleSearchTree, "app.bsky.feed.post/nonexistent" # Nat.toText(i))) {
              case (#ok(_)) #err("Removed nonexistent key");
              case (#err(_)) #ok;
            };
          };

          case ("validate") func(_ : Nat) : Result.Result<Any, Text> {
            MerkleSearchTree.validate(populatedMerkleSearchTree);
          };

          case ("size") func(_ : Nat) : Result.Result<Any, Text> {
            ignore MerkleSearchTree.size(populatedMerkleSearchTree);
            #ok;
          };

          case (_) Runtime.trap("Unknown row: " # row);
        };

        for (i in Nat.range(1, n + 1)) {
          switch (operation(i)) {
            case (#ok(_)) ();
            case (#err(e)) Runtime.trap(e);
          };
        };
      }
    );

    bench;
  };
};
