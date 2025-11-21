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
