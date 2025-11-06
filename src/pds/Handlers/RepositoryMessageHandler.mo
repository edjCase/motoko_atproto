import TID "mo:tid@1";
import CID "mo:cid@1";
import DID "mo:did@3";
import Result "mo:core@1/Result";
import Queue "mo:core@1/Queue";
import PureQueue "mo:core@1/pure/Queue";
import SubscribeRepos "../../atproto/Lexicons/Com/Atproto/Sync/SubscribeRepos";
import DateTime "mo:datetime@1/DateTime";
import Array "mo:core@1/Array";
import List "mo:core@1/List";
import Runtime "mo:core@1/Runtime";
import Repository "../../atproto/Repository";

module {

  public type Event = {
    #commit : Commit;
  };

  public type Commit = {
    repo : DID.Plc.DID;
    commit : CID.CID;
    rev : TID.TID;
    blocks : Blob;
    ops : [Operation];
    prevData : ?CID.CID;
  };

  public type Operation = {
    action : Action;
    key : Repository.Key;
  };

  public type Action = {
    #create : { cid : CID.CID };
    #update : { newCid : CID.CID; prevCid : CID.CID };
    #delete : { cid : CID.CID };
  };

  public type QueueMessage = {
    #commit : SubscribeRepos.Commit;
  };

  public type Message = QueueMessage or {
    #info : SubscribeRepos.Info;
  };

  public type StableData = {
    messages : PureQueue.Queue<QueueMessage>;
    seq : Nat;
    lastRev : ?TID.TID;
    maxEventCount : Nat;
  };

  public class Handler(stableData : StableData) {
    let messages = Queue.fromPure<QueueMessage>(stableData.messages);
    var seq : Nat = if (stableData.seq < 1) {
      1; // Minimum seq starts at 1
    } else {
      stableData.seq;
    };
    var lastRev : ?TID.TID = stableData.lastRev;
    let maxEventCount : Nat = stableData.maxEventCount;

    public func addEvent(event : Event) {
      let (message, rev) : (QueueMessage, TID.TID) = switch (event) {
        case (#commit(c)) {
          let message : QueueMessage = #commit({
            seq = seq;
            rebase = false; // deprecated
            tooBig = false; // deprecated
            repo = c.repo;
            commit = c.commit;
            rev = c.rev;
            since = lastRev;
            blocks = c.blocks;
            ops = convertOps(c.ops);
            blobs = []; // deprecated
            prevData = c.prevData;
            time = DateTime.now().toTextFormatted(#iso);
          });
          (message, c.rev);
        };
      };

      Queue.pushBack(messages, message);
      seq += 1;
      lastRev := ?rev;

      if (Queue.size(messages) > maxEventCount) {
        ignore Queue.popFront(messages);
      };
    };

    public func getMessages(seqCursor : Nat) : Result.Result<[Message], SubscribeRepos.Error> {
      if (Queue.isEmpty(messages)) {
        return #ok([]);
      };

      let ?newest = Queue.peekBack(messages) else Runtime.unreachable();
      let newestSeq = getSeq(newest);
      if (seqCursor > newestSeq) {
        return #err(#futureCursor);
      };

      let ?oldest = Queue.peekFront(messages) else Runtime.unreachable();
      let oldestSeq = getSeq(oldest);

      let newMessages = List.empty<Message>();
      if (seqCursor != 0 and seqCursor < oldestSeq) {
        // Add info message saying that the cursor is outdated
        let info = {
          name = #outdatedCursor;
          message = ?"The provided cursor is too old and some events may have been missed.";
        };
        List.add<Message>(newMessages, #info(info));
      };

      for (message in Queue.values(messages)) {
        // Only include messages newer than seqCursor, otherwise discard
        if (getSeq(message) > seqCursor) {
          List.add(newMessages, message);
        };
      };

      #ok(List.toArray(newMessages));
    };

    public func toStableData() : StableData {
      {
        messages = Queue.toPure(messages);
        seq = seq;
        lastRev = lastRev;
        maxEventCount = maxEventCount;
      };
    };

    func getSeq(msg : QueueMessage) : Int {
      switch (msg) {
        case (#commit(c)) c.seq;
      };
    };

    func convertOps(ops : [Operation]) : [SubscribeRepos.RepoOp] {
      Array.map<Operation, SubscribeRepos.RepoOp>(
        ops,
        func(op) {
          {
            action = switch (op.action) {
              case (#create(_)) #create;
              case (#update(_)) #update;
              case (#delete(_)) #delete;
            };
            path = Repository.keyToText(op.key);
            cid = switch (op.action) {
              case (#create(c)) ?c.cid;
              case (#update(u)) ?u.newCid;
              case (#delete(_)) null;
            };
            prev = switch (op.action) {
              case (#create(_)) null;
              case (#update(u)) ?u.prevCid;
              case (#delete(d)) ?d.cid;
            };
          };
        },
      );
    };
  };
};
