import Bench "mo:bench";
import Nat "mo:core@1/Nat";
import Result "mo:core@1/Result";
import Blob "mo:core@1/Blob";
import Runtime "mo:core@1/Runtime";
import CID "mo:cid@1";
import MerkleSearchTree "../src/atproto/MerkleSearchTree";
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

    let bench = Bench.Bench();

    bench.name("MerkleSearchTree Batch Operations Benchmarks");
    bench.description("Benchmark batch MerkleSearchTree operations");

    bench.rows([
      "add_batch_1",
      "add_batch_10",
      "add_batch_100",
      "add_batch_1000",
    ]);

    bench.cols(["1", "10"]);

    func batch(size : Nat) : Result.Result<(), Text> {
      var mst = MerkleSearchTree.empty();
      let items = Array.tabulate<(Text, CID.CID)>(
        size,
        func(j) = (Nat.toText(j), testCID1),
      );
      switch (MerkleSearchTree.addMany(mst, items.vals())) {
        case (#ok(_)) #ok;
        case (#err(e)) #err(e);
      };
    };

    bench.runner(
      func(row, col) {
        let ?n = Nat.fromText(col) else Runtime.trap("Cols must only contain numbers: " # col);

        let count = switch (row) {
          case ("add_batch_1") 1;
          case ("add_batch_10") 10;
          case ("add_batch_100") 100;
          case ("add_batch_1000") 1000;
          case (_) Runtime.trap("Unknown row: " # row);
        };

        for (i in Nat.range(1, n + 1)) {
          switch (batch(count)) {
            case (#ok(_)) ();
            case (#err(e)) Runtime.trap(e);
          };
        };
      }
    );

    bench;
  };
};
