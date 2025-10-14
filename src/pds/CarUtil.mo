import Text "mo:core@1/Text";
import Result "mo:core@1/Result";
import DID "mo:did@3";
import TID "mo:tid@1";
import CID "mo:cid@1";
import PureMap "mo:core@1/pure/Map";
import CAR "mo:car@1";
import MerkleSearchTree "../atproto/MerkleSearchTree";
import DagCbor "mo:dag-cbor@2";
import Commit "../atproto/Commit";
import BlobRef "../atproto/BlobRef";
import CIDBuilder "../atproto/CIDBuilder";
import Blob "mo:core@1/Blob";
import Int "mo:core@1/Int";
import Repository "../atproto/Repository";
import List "mo:core@1/List";
import DynamicArray "mo:xtended-collections@0/DynamicArray";
import MerkleNode "../atproto/MerkleNode";

module {
  public func buildRepository(request : CAR.File) : Result.Result<(DID.Plc.DID, Repository.Repository), Text> {
    let roots = request.header.roots;
    if (roots.size() == 0) {
      return #err("CAR file has no root CIDs");
    };

    // Build maps for quick lookup of blocks
    var blockMap = PureMap.empty<CID.CID, Blob>();
    for (block in request.blocks.vals()) {
      blockMap := PureMap.add(blockMap, CIDBuilder.compare, block.cid, block.data);
    };

    // Find the latest commit (should be first root)
    let latestCommitCID = roots[0];
    let ?latestCommitData = PureMap.get(blockMap, CIDBuilder.compare, latestCommitCID) else {
      return #err("Latest commit block not found");
    };

    // Decode the commit
    let latestCommit = switch (DagCbor.fromBytes(latestCommitData.vals())) {
      case (#ok(commitValue)) {
        switch (parseCommitFromCbor(commitValue)) {
          case (#ok(commit)) commit;
          case (#err(e)) return #err("Failed to parse commit: " # e);
        };
      };
      case (#err(e)) return #err("Failed to decode commit CBOR: " # debug_show (e));
    };

    // Reconstruct repository state
    var allRecords = PureMap.empty<CID.CID, DagCbor.Value>();
    var allCommits = PureMap.empty<CID.CID, Commit.Commit>();
    var allBlobs = PureMap.empty<CID.CID, BlobRef.BlobRef>();

    // Reconstruct MST from the data CID in latest commit
    let mst = switch (MerkleSearchTree.fromBlockMap(latestCommitCID, blockMap)) {
      case (#err(e)) return #err("Failed to reconstruct MST: " # e);
      case (#ok(mst)) mst;
    };

    // Extract all records referenced by the MST
    switch (extractAllRecords(mst, blockMap)) {
      case (#err(e)) return #err("Failed to extract records: " # e);
      case (#ok(records)) allRecords := records;
    };

    // Reconstruct commit history
    var currentCommitInfo : (CID.CID, Commit.Commit) = (latestCommitCID, latestCommit);
    label w while (true) {
      allCommits := PureMap.add(allCommits, CIDBuilder.compare, currentCommitInfo.0, currentCommitInfo.1);

      let ?prevCID = currentCommitInfo.1.prev else break w;
      let ?prevData = PureMap.get(blockMap, CIDBuilder.compare, prevCID) else break w;

      let prevCommit = switch (DagCbor.fromBytes(prevData.vals())) {
        case (#ok(prevValue)) {
          switch (parseCommitFromCbor(prevValue)) {
            case (#ok(prevCommit)) prevCommit;
            case (#err(e)) return #err("Failed to parse previous commit: " # e);
          };
        };
        case (#err(e)) return #err("Failed to decode previous commit CBOR: " # debug_show (e));
      };
      currentCommitInfo := (prevCID, prevCommit);
    };

    // Create repository
    let repository : Repository.Repository = {
      head = latestCommitCID;
      rev = latestCommit.rev;
      active = true;
      status = null;
      commits = allCommits;
      records = allRecords;
      nodes = mst.nodes;
      blobs = allBlobs;
    };
    #ok((latestCommit.did, repository));
  };

  public func fromRepository(
    repository : Repository.Repository,
    sinceOrNull : ?TID.TID,
  ) : Result.Result<CAR.File, Text> {

    let exportData = switch (Repository.exportData(repository, sinceOrNull)) {
      case (#err(e)) return #err("Failed to export repository data: " # e);
      case (#ok(data)) data;
    };

    let blocks = List.empty<CAR.Block>();

    // Add commit blocks
    for ((cid, commit) in exportData.commits.vals()) {
      let cborValue = commitToCbor(commit);
      let cborBytes = switch (DagCbor.toBytes(cborValue)) {
        case (#ok(bytes)) bytes;
        case (#err(e)) return #err("Failed to encode commit to CBOR: " # debug_show (e));
      };
      let block : CAR.Block = {
        cid = cid;
        data = Blob.fromArray(cborBytes);
      };
      List.add(blocks, block);
    };

    // Add record blocks
    for ((cid, record) in exportData.records.vals()) {
      let cborBytes = switch (DagCbor.toBytes(record)) {
        case (#ok(bytes)) bytes;
        case (#err(e)) return #err("Failed to encode record to CBOR: " # debug_show (e));
      };
      let block : CAR.Block = {
        cid = cid;
        data = Blob.fromArray(cborBytes);
      };
      List.add(blocks, block);
    };

    // Add node blocks
    for ((cid, node) in exportData.nodes.vals()) {
      let cborValue = nodeToCbor(node);
      let cborBytes = switch (DagCbor.toBytes(cborValue)) {
        case (#ok(bytes)) bytes;
        case (#err(e)) return #err("Failed to encode node to CBOR: " # debug_show (e));
      };
      let block : CAR.Block = {
        cid = cid;
        data = Blob.fromArray(cborBytes);
      };
      List.add(blocks, block);
    };

    #ok({
      header = {
        version = 1;
        roots = [repository.head];
      };
      blocks = List.toArray(blocks);
    });
  };

  private func nodeToCbor(node : MerkleNode.Node) : DagCbor.Value {
    let size = if (node.leftSubtreeCID == null) 1 else 2;
    let fields = DynamicArray.DynamicArray<(Text, DagCbor.Value)>(size);

    switch (node.leftSubtreeCID) {
      case (?cid) {
        fields.add(("l", #cid(cid)));
      };
      case (null) {};
    };

    let entryArray = DynamicArray.DynamicArray<DagCbor.Value>(node.entries.size());
    for (entry in node.entries.vals()) {
      entryArray.add(entryToCbor(entry));
    };
    fields.add(("e", #array(DynamicArray.toArray(entryArray))));

    #map(DynamicArray.toArray(fields));
  };

  private func entryToCbor(entry : MerkleNode.TreeEntry) : DagCbor.Value {
    let size = if (entry.subtreeCID == null) 3 else 4;
    let fields = DynamicArray.DynamicArray<(Text, DagCbor.Value)>(size);

    fields.add(("p", #int(entry.prefixLength)));
    fields.add(("k", #bytes(entry.keySuffix)));
    fields.add(("v", #cid(entry.valueCID)));

    switch (entry.subtreeCID) {
      case (?cid) {
        fields.add(("t", #cid(cid)));
      };
      case (null) {};
    };

    #map(DynamicArray.toArray(fields));
  };

  private func commitToCbor(commit : Commit.Commit) : DagCbor.Value {
    let size = if (commit.prev == null) 5 else 6;
    let fields = DynamicArray.DynamicArray<(Text, DagCbor.Value)>(size);
    fields.add(("did", #text(DID.Plc.toText(commit.did))));
    fields.add(("version", #int(commit.version)));
    fields.add(("data", #cid(commit.data)));
    fields.add(("rev", #text(TID.toText(commit.rev))));
    fields.add(("sig", #bytes(Blob.toArray(commit.sig))));

    switch (commit.prev) {
      case (?prevCID) {
        fields.add(("prev", #cid(prevCID)));
      };
      case (null) ();
    };

    #map(DynamicArray.toArray(fields));
  };

  // Helper function to extract all records from MST
  private func extractAllRecords(
    mst : MerkleSearchTree.MerkleSearchTree,
    blockMap : PureMap.Map<CID.CID, Blob>,
  ) : Result.Result<PureMap.Map<CID.CID, DagCbor.Value>, Text> {
    var records = PureMap.empty<CID.CID, DagCbor.Value>();

    // Get all CID references from MST - need to find root from latest commit
    // This function is called with an MST reconstructed from blocks, so we need to find the root
    // For now, get the first node as root (this may need refinement for complex MSTs)

    for (cid in MerkleSearchTree.values(mst)) {
      let ?blockData = PureMap.get(blockMap, CIDBuilder.compare, cid) else {
        return #err("Record block not found: " # CID.toText(cid));
      };

      switch (DagCbor.fromBytes(blockData.vals())) {
        case (#ok(value)) {
          records := PureMap.add(records, CIDBuilder.compare, cid, value);
        };
        case (#err(e)) {
          return #err("Failed to decode record: " # debug_show (e));
        };
      };
    };

    #ok(records);
  };

  // Helper function to parse commit from CBOR value
  private func parseCommitFromCbor(value : DagCbor.Value) : Result.Result<Commit.Commit, Text> {
    switch (value) {
      case (#map(fields)) {
        var did : ?DID.Plc.DID = null;
        var version : ?Nat = null;
        var data : ?CID.CID = null;
        var rev : ?TID.TID = null;
        var prev : ?CID.CID = null;
        var sig : ?Blob = null;

        for ((key, val) in fields.vals()) {
          switch (key, val) {
            case ("did", #text(didText)) {
              switch (DID.Plc.fromText(didText)) {
                case (#ok(d)) did := ?d;
                case (#err(_)) return #err("Invalid DID in commit");
              };
            };
            case ("version", #int(v)) version := ?Int.abs(v);
            case ("data", #cid(cid)) {
              data := ?cid;
            };
            case ("rev", #text(revText)) {
              switch (TID.fromText(revText)) {
                case (#ok(r)) rev := ?r;
                case (#err(_)) return #err("Invalid rev in commit");
              };
            };
            case ("prev", #cid(cid)) {
              prev := ?cid;
            };
            case ("sig", #bytes(sigBytes)) sig := ?Blob.fromArray(sigBytes);
            case _ ();
          };
        };

        let ?d = did else return #err("Missing did in commit");
        let ?v = version else return #err("Missing version in commit");
        let ?dt = data else return #err("Missing data in commit");
        let ?r = rev else return #err("Missing rev in commit");
        let ?s = sig else return #err("Missing sig in commit");

        #ok({
          did = d;
          version = v;
          data = dt;
          prev = prev;
          rev = r;
          sig = s;
        });
      };
      case _ #err("Commit must be a CBOR map");
    };
  };
};
