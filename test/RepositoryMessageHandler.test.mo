import CID "mo:cid@1";
import Text "mo:core@1/Text";
import { test } "mo:test";
import Sha256 "mo:sha2@0/Sha256";
import Nat "mo:core@1/Nat";
import RepositoryMessageHandler "../src/pds/Handlers/RepositoryMessageHandler";
import PureQueue "mo:core@1/pure/Queue";
import Option "mo:core@1/Option";
import DID "mo:did@3";
import Blob "mo:core@1/Blob";
import Runtime "mo:core@1/Runtime";

func emptyHandler(startingSeq : ?Nat, maxEventCount : ?Nat) : RepositoryMessageHandler.Handler {
  RepositoryMessageHandler.Handler({
    messages = PureQueue.empty<RepositoryMessageHandler.QueueMessage>();
    seq = Option.get(startingSeq, 1);
    lastRev = null;
    maxEventCount = Option.get(maxEventCount, 1000);
  });
};
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
func createTestDID() : DID.Plc.DID {
  { identifier = "test123456789abcdefghijk" };
};

test(
  "Add 2 events, get all, expect 2 message",
  func() {
    let handler = emptyHandler(null, null);

    let event : RepositoryMessageHandler.Event = #commit({
      blocks = Blob.empty();
      commit = createTestCID("commit1");
      ops = [];
      prevData = null;
      repo = createTestDID();
      rev = {
        clockId = 1;
        timestamp = 1;
      };
    });
    handler.addEvent(event);
    handler.addEvent(event);

    let messages = switch (handler.getMessages(0)) {
      case (#ok(msgs)) msgs;
      case (#err(err)) Runtime.trap("Failed to get messages: " # debug_show (err));
    };
    if (messages.size() != 2) {
      Runtime.trap("Expected 2 message after adding event, got " # Nat.toText(messages.size()) # "\nMessages: " # debug_show (messages));
    };
  },
);
test(
  "Add event, get all multiple times, expect 1 message each time",
  func() {
    let handler = emptyHandler(null, null);

    let event : RepositoryMessageHandler.Event = #commit({
      blocks = Blob.empty();
      commit = createTestCID("commit1");
      ops = [];
      prevData = null;
      repo = createTestDID();
      rev = {
        clockId = 1;
        timestamp = 1;
      };
    });
    handler.addEvent(event);

    for (i in Nat.range(0, 3)) {
      let messages = switch (handler.getMessages(0)) {
        case (#ok(msgs)) msgs;
        case (#err(err)) Runtime.trap("Failed to get messages: " # debug_show (err));
      };
      if (messages.size() != 1) {
        Runtime.trap("Expected 1 message after adding event (iteration " # Nat.toText(i) # "), got " # Nat.toText(messages.size()) # "\nMessages: " # debug_show (messages));
      };
    };
  },
);

test(
  "Add 1 event, cursor in future, error",
  func() {
    let handler = emptyHandler(null, null);

    let event : RepositoryMessageHandler.Event = #commit({
      blocks = Blob.empty();
      commit = createTestCID("commit1");
      ops = [];
      prevData = null;
      repo = createTestDID();
      rev = {
        clockId = 1;
        timestamp = 1;
      };
    });
    handler.addEvent(event);

    switch (handler.getMessages(5)) {
      case (#ok(_)) Runtime.trap("Expected error for future cursor");
      case (#err(err)) {
        if (err != #futureCursor) {
          Runtime.trap("Expected futureCursor error, got " # debug_show (err));
        };
      };
    };
  },
);
test(
  "Add 2 event, seq = 1, expect 1 message",
  func() {
    let handler = emptyHandler(null, null);

    let event : RepositoryMessageHandler.Event = #commit({
      blocks = Blob.empty();
      commit = createTestCID("commit1");
      ops = [];
      prevData = null;
      repo = createTestDID();
      rev = {
        clockId = 1;
        timestamp = 1;
      };
    });
    handler.addEvent(event);
    handler.addEvent(event);

    let messages = switch (handler.getMessages(1)) {
      case (#ok(msgs)) msgs;
      case (#err(err)) Runtime.trap("Failed to get messages: " # debug_show (err));
    };
    if (messages.size() != 1) {
      Runtime.trap("Expected 1 message after adding event, got " # Nat.toText(messages.size()));
    };
  },
);

test(
  "Add events, first seq is 2, get outdatedCursor info + messages",
  func() {
    let handler = emptyHandler(?2, null);

    let event : RepositoryMessageHandler.Event = #commit({
      blocks = Blob.empty();
      commit = createTestCID("commit1");
      ops = [];
      prevData = null;
      repo = createTestDID();
      rev = {
        clockId = 1;
        timestamp = 1;
      };
    });
    handler.addEvent(event);

    let messages = switch (handler.getMessages(1)) {
      case (#ok(msgs)) msgs;
      case (#err(err)) Runtime.trap("Failed to get messages: " # debug_show (err));
    };
    if (messages.size() != 2) {
      Runtime.trap("Expected 2 message after adding event, got " # Nat.toText(messages.size()));
    };
    switch (messages[0]) {
      case (#info(info)) {
        if (info.name != #outdatedCursor) {
          Runtime.trap("Expected outdatedCursor info message, got " # debug_show (info));
        };
      };
      case (_) Runtime.trap("Expected info message first, got " # debug_show (messages[0]));
    };
    switch (messages[1]) {
      case (#commit(_)) {};
      case (_) Runtime.trap("Expected commit message second, got " # debug_show (messages[1]));
    };
  },
);
test(
  "Add events over maxEventCount, only have maxEventCount events stored",
  func() {
    let maxEventCount : Nat = 5;
    let handler = emptyHandler(null, ?maxEventCount);

    let event : RepositoryMessageHandler.Event = #commit({
      blocks = Blob.empty();
      commit = createTestCID("commit1");
      ops = [];
      prevData = null;
      repo = createTestDID();
      rev = {
        clockId = 1;
        timestamp = 1;
      };
    });
    for (_ in Nat.range(0, maxEventCount + 3)) { handler.addEvent(event) };

    let messages = switch (handler.getMessages(0)) {
      case (#ok(msgs)) msgs;
      case (#err(err)) Runtime.trap("Failed to get messages: " # debug_show (err));
    };
    if (messages.size() != maxEventCount) {
      Runtime.trap("Expected " # Nat.toText(maxEventCount) # " messages after adding event, got " # Nat.toText(messages.size()));
    };
  },
);
