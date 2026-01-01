import { test } "mo:test";
import CIDBuilder "../src/CIDBuilder";
import CID "mo:cid@1";
import Runtime "mo:core@1/Runtime";

test(
  "CID validation",
  func() {
    let testCases = [{
      node = {
        leftSubtreeCID = null;
        entries = [];
      };
      expected = "bafyreie5737gdxlw5i64vzichcalba3z2v5n6icifvx5xytvske7mr3hpm";
    }];

    for (testCase in testCases.vals()) {
      let cid = CIDBuilder.fromMSTNode(testCase.node);
      let rootCIDText = CID.toText(cid);
      if (rootCIDText != testCase.expected) {
        Runtime.trap(
          "CID mismatch\n" #
          "Expected: " # testCase.expected # "\n" #
          "Got:      " # rootCIDText
        );
      };
    };
  },
);

// test(
//   "CID fromRecord",
//   func() {
//     let testCases = [{
//       key = "app.bsky.feed.post/3m66an3m5vp22";
//       record = #map([
//         ("$type", #text("app.bsky.feed.post")),
//         ("text", #text("Hello World!")),
//         ("createdAt", #text("2025-11-21T21:39:31.533685647Z")),
//       ]);
//       expected = "bafyreicvobsaopq4ddor5b4a4flmcnhr4yrm3hhyzwtdybadouau7roylm";
//     }];
//     for (testCase in testCases.vals()) {
//       let cid = CIDBuilder.fromRecord(testCase.key, testCase.record);
//       let cidText = CID.toText(cid);
//       if (cidText != testCase.expected) {
//         Runtime.trap(
//           "CID mismatch\n" #
//           "Expected: " # testCase.expected # "\n" #
//           "Got:      " # cidText
//         );
//       };
//     };
//   },
// );
