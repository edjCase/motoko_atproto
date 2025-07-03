import Repository "../Types/Repository";
import DID "mo:did";
import CID "mo:cid";
import TID "mo:tid";
import Array "mo:new-base/Array";
import PureMap "mo:new-base/pure/Map";
import Commit "../Types/Commit";
import DagCbor "mo:dag-cbor";
import MST "../Types/MST";
import CIDBuilder "../CIDBuilder";
import AtUri "../Types/AtUri";
import Result "mo:base/Result";
import KeyHandler "../Handlers/KeyHandler";
import Text "mo:new-base/Text";
import Order "mo:new-base/Order";
import Blob "mo:new-base/Blob";
import MSTHandler "../Handlers/MSTHandler";

module {
    public type StableData = {
        repositories : PureMap.Map<DID.Plc.DID, RepositoryWithData>;
    };

    public type RepositoryWithData = Repository.RepositoryWithoutDID and {
        commits : [Commit.Commit];
        records : PureMap.Map<CID.CID, DagCbor.Value>;
        nodes : PureMap.Map<Text, MST.Node>;
    };

    public class Handler(
        stableData : StableData,
        keyHandler : KeyHandler.Handler,
        tidGenerator : TID.Generator,
    ) {
        var repositories = stableData.repositories;

        public func getAll() : [Repository.Repository] {
            return repositories;
        };

        public func get(repoId : DID.Plc.DID) : ?Repository.Repository {
            let ?repo = Map.get(repositories, comparePlcDID, repoId) else return null;
            {
                repo with
                did = repoId;
            };
        };

        public func create(
            plcDid : DID.Plc.DID,
            head : CID.CID,
        ) : Repository.Repository {
            let newRepo = {
                did = plcDid;
                head = head;
                rev = tidGenerator.next();
                active = true;
                status = null;
                commits = [];
                records = PureMap.empty<CID.CID, DagCbor.Value>();
            };
            repositories := Array.concat(repositories, [newRepo]);
            return newRepo;
        };

        public func addRecord(
            repoDid : DID.Plc.DID,
            collectionId : Text,
            key : Text,
            value : DagCbor.Value,
        ) : async* Result.Result<(), Text> {

            let ?repo = PureMap.get(repositories, comparePlcDID, repoId) else return #err("Repository not found: " # DID.Plc.toText(repoDid));

            let recordCID = CIDBuilder.fromRecord(key, value);
            let updatedRecords = PureMap.add(repo.records, compareCID, recordCID, value);

            // Create record path
            let path = AtUri.toText({ collectionId; recordKey = key });
            let pathKey = MST.pathToKey(path);

            let mstHandler = MSTHandler.Handler(repo.nodes);

            // Add to MST
            let newMST = switch (mstHandler.addCID(currentMST, pathKey, recordCID)) {
                case (#ok(mst)) mst;
                case (#err(e)) return #err("Failed to add to MST: " # debug_show (e));
            };

            // Create new commit
            let newRev = tidGenerator.next();
            let mstRootCID = CIDBuilder.fromMSTNode(newMST);

            let unsignedCommit = {
                did = repoDid;
                version = 1; // TODO?
                data = mstRootCID;
                rev = newRev;
                prev = currentHead;
            };

            // Sign commit
            let signedCommit = switch (await* signCommit(unsignedCommit)) {
                case (#ok(commit)) commit;
                case (#err(e)) return #err("Failed to sign commit: " # e);
            };

            // Store new state
            let commitCID = CIDBuilder.fromCommit(signedCommit);
            let updatedCommits = PureMap.add<TID.TID, Commit.Commit>(repo.commits, TID.compare, newRev, signedCommit);

            repositories := PureMap.add(
                repositories,
                comparePlcDID,
                repoDid,
                {
                    repo with
                    head = commitCID;
                    rev = newRev;
                    commits = updatedCommits;
                    records = updatedRecords;
                    nodes = mstHandler.toStableData();
                },
            );

            #ok;
        };

        public func getRecord(
            repoDid : DID.Plc.DID,
            collectionId : Text,
            recordKey : Text,
        ) : ?DagCbor.Value {
            let ?repo = PureMap.get(repositories, comparePlcDID, repoDid) else return #err("Repository not found: " # DID.Plc.toText(repoDid));

            let path = AtUri.toText({ collectionId; recordKey });
            let pathKey = MST.pathToKey(path);

            let mstHandler = MSTHandler.Handler(repo.nodes);

            let rootNode =;

            let ?recordCID = mstHandler.getCID(rootNode, pathKey) else return null;
            PureMap.get(repo.records, compareCID, recordCID);
        };

        public func toStableData() : StableData {
            return {
                repositories = repositories;
            };
        };

        private func signCommit(unsigned : Commit.UnsignedCommit) : async* Result.Result<Commit.Commit, Text> {
            // Serialize unsigned commit to CBOR
            let cid = CIDBuilder.fromUnsignedCommit(unsigned);
            let hash = CID.getHash(cid);

            // Sign with rotation key
            let signature = switch (await* keyHandler.sign(#rotation, hash)) {
                case (#ok(sig)) sig;
                case (#err(e)) return #err(e);
            };

            #ok({
                unsigned with
                sig = signature;
            });
        };

        func compareCID(cid1 : CID.CID, cid2 : CID.CID) : Order.Order {
            // TODO is this the right way to compare CIDs?
            if (cid1 == cid2) return #equal;

            let hash1 = CID.getHash(cid1);
            let hash2 = CID.getHash(cid2);
            Blob.compare(hash1, hash2);
        };

        func comparePlcDID(did1 : DID.Plc.DID, did2 : DID.Plc.DID) : Order.Order {
            if (did1 == did2) return #equal;
            Text.compare(did1.identifier, did2.identifier);
        };
    };
};
