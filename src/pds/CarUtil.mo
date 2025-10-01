import Text "mo:core@1/Text";
import Result "mo:core@1/Result";
import RepositoryHandler "Handlers/RepositoryHandler";
import ServerInfo "ServerInfo";
import DID "mo:did@3";
import TID "mo:tid@1";
import CID "mo:cid@1";
import PureMap "mo:core@1/pure/Map";
import Json "mo:json@1";
import Principal "mo:core@1/Principal";
import CAR "mo:car@1";
import MerkleSearchTree "../atproto/MerkleSearchTree";
import DagCbor "mo:dag-cbor@2";
import Commit "../atproto/Commit";
import BlobRef "../atproto/BlobRef";
import CIDBuilder "../atproto/CIDBuilder";
import Blob "mo:core@1/Blob";
import Int "mo:core@1/Int";

module {
  public func buildRepository(request : CAR.File) : Result.Result<(DID.Plc.DID, RepositoryHandler.Repository), Text> {
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
    var allCommits = PureMap.empty<TID.TID, Commit.Commit>();
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
    var currentCommitOpt : ?Commit.Commit = ?latestCommit;
    label w while (true) {
      switch (currentCommitOpt) {
        case (null) break w;
        case (?commit) {
          allCommits := PureMap.add(allCommits, TID.compare, commit.rev, commit);

          switch (commit.prev) {
            case (null) currentCommitOpt := null;
            case (?prevCID) {
              let ?prevData = PureMap.get(blockMap, CIDBuilder.compare, prevCID) else {
                currentCommitOpt := null;
                break w;
              };

              switch (DagCbor.fromBytes(prevData.vals())) {
                case (#ok(prevValue)) {
                  switch (parseCommitFromCbor(prevValue)) {
                    case (#ok(prevCommit)) currentCommitOpt := ?prevCommit;
                    case (#err(_)) currentCommitOpt := null;
                  };
                };
                case (#err(_)) currentCommitOpt := null;
              };
            };
          };
        };
      };
    };

    // Create repository
    let repository = {
      head = latestCommitCID;
      rev = latestCommit.rev;
      active = true;
      status = null;
      commits = allCommits;
      records = allRecords;
      nodes = mst.getNodes();
      blobs = allBlobs;
    };
    #ok((latestCommit.did, repository));
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
    let nodes = mst.getNodes();
    let ?rootNode = switch (PureMap.entries(nodes) |> _.next()) {
      case (?(_, node)) ?node;
      case (null) null;
    } else return #err("No MST nodes found");

    let allCIDs = mst.getAllRecordCIDs(rootNode);

    for (cid in allCIDs.vals()) {
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
