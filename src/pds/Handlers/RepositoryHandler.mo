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
import Iter "mo:new-base/Iter";
import LexiconValidator "../LexiconValidator";
import Debug "mo:new-base/Debug";

module {
    public type StableData = {
        repositories : PureMap.Map<DID.Plc.DID, RepositoryWithData>;
    };

    type Commit = {
        did : DID.Plc.DID;
        version : Nat;
        data : CID.CID;
        prev : ?CID.CID;
        sig : Blob;
    };

    public type RepositoryWithData = Repository.RepositoryWithoutDID and {
        commits : PureMap.Map<TID.TID, Commit>;
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
            return PureMap.entries(repositories)
            |> Iter.map(
                _,
                func((did, repo) : (DID.Plc.DID, RepositoryWithData)) : Repository.Repository {
                    {
                        repo with
                        did = did;
                    };
                },
            )
            |> Iter.toArray(_);
        };

        public func get(id : DID.Plc.DID) : ?Repository.Repository {
            let ?repo = PureMap.get(repositories, comparePlcDID, id) else return null;
            ?{
                repo with
                did = id;
            };
        };

        public func create(
            id : DID.Plc.DID
        ) : async* Result.Result<Repository.Repository, Text> {

            let mstHandler = MSTHandler.Handler(PureMap.empty<Text, MST.Node>());
            // First node is empty
            let newMST : MST.Node = {
                l = null;
                e = [];
            };
            let rev = tidGenerator.next();
            let newMSTCID = mstHandler.addNode(newMST);
            let signedCommit = switch (await* createCommit(id, rev, newMSTCID, null)) {
                case (#ok(commit)) commit;
                case (#err(e)) return #err("Failed to create commit: " # e);
            };
            let signedCommitCID = CIDBuilder.fromCommit(signedCommit);
            let newRepo : RepositoryWithData = {
                head = signedCommitCID;
                rev = rev;
                active = true;
                status = null;
                commits = PureMap.singleton<TID.TID, Commit>(rev, signedCommit);
                records = PureMap.empty<CID.CID, DagCbor.Value>();
                nodes = mstHandler.getNodes();
            };
            let (newRepositories, idExists) = PureMap.insert(
                repositories,
                comparePlcDID,
                id,
                newRepo,
            );
            if (idExists) {
                return #err("Repository with DID " # DID.Plc.toText(id) # " already exists");
            };
            repositories := newRepositories;
            #ok({
                newRepo with
                did = id;
            });
        };

        public func createRecord(
            request : Repository.CreateRecordRequest
        ) : async* Result.Result<Repository.CreateRecordResponse, Text> {

            let ?_ = get(request.repo) else return #err("Repository not found: " # DID.Plc.toText(request.repo));

            let rKey : Text = switch (request.rkey) {
                case (?rkey) {
                    if (Text.size(rkey) > 512) {
                        return #err("Record key exceeds maximum length of 512 characters");
                    };
                    rkey;
                };
                case (null) TID.toText(tidGenerator.next());
            };

            switch (request.swapCommit) {
                case (?_) {
                    // Handle swapCommit field
                    Debug.todo();
                };
                case (null) ();
            };

            let validationResult : Result.Result<Repository.ValidationStatus, Text> = switch (request.validate) {
                case (?true) LexiconValidator.validateRecord(request.record, request.collection, false);
                case (?false) #ok(#unknown);
                case (null) LexiconValidator.validateRecord(request.record, request.collection, true);
            };
            let validationStatus = switch (validationResult) {
                case (#ok(status)) status;
                case (#err(e)) return #err("Record validation failed: " # e);
            };

            let ?repo = PureMap.get(repositories, comparePlcDID, request.repo) else return #err("Repository not found: " # DID.Plc.toText(request.repo));

            let recordCID = CIDBuilder.fromRecord(rKey, request.record);
            let updatedRecords = PureMap.add(repo.records, compareCID, recordCID, request.record);

            // Create record path
            let path = AtUri.toText({
                repoId = request.repo;
                collectionAndRecord = ?(request.collection, ?rKey);
            });
            let pathKey = MST.pathToKey(path);

            let mstHandler = MSTHandler.Handler(repo.nodes);

            // Get current MST root from the latest commit
            let ?currentCommit = PureMap.get<TID.TID, Commit>(
                repo.commits,
                TID.compare,
                repo.rev,
            ) else return #err("No commits found in repository");

            let currentNodeCID = currentCommit.data;

            // Add to MST
            let newNode = switch (mstHandler.addCID(currentCommit.data, pathKey, recordCID)) {
                case (#ok(mst)) mst;
                case (#err(e)) return #err("Failed to add to MST: " # debug_show (e));
            };

            let newNodeCID = CIDBuilder.fromMSTNode(newNode);
            // Create new commit
            let newRev = tidGenerator.next();

            let signedCommit = switch (
                await* createCommit(
                    request.repo,
                    newRev,
                    newNodeCID,
                    ?currentNodeCID,
                )
            ) {
                case (#ok(commit)) commit;
                case (#err(e)) return #err("Failed to create commit: " # e);
            };

            // Store new state
            let commitCID = CIDBuilder.fromCommit(signedCommit);
            let updatedCommits = PureMap.add<TID.TID, Commit>(
                repo.commits,
                TID.compare,
                newRev,
                signedCommit,
            );

            repositories := PureMap.add(
                repositories,
                comparePlcDID,
                request.repo,
                {
                    repo with
                    head = commitCID;
                    rev = newRev;
                    commits = updatedCommits;
                    records = updatedRecords;
                    nodes = mstHandler.getNodes();
                },
            );

            #ok({
                cid = recordCID;
                commit = ?{
                    cid = commitCID;
                    rev = newRev;
                };
                uri = {
                    repoId = request.repo;
                    collectionAndRecord = ?(request.collection, ?rKey);
                };
                validationStatus = validationStatus;
            });
        };

        public func getRecord(
            repoId : DID.Plc.DID,
            collectionId : Text,
            recordKey : Text,
        ) : ?{
            cid : CID.CID;
            value : DagCbor.Value;
        } {
            let ?repo = PureMap.get(repositories, comparePlcDID, repoId) else return null;

            let path = collectionId # "/" # recordKey;
            let pathKey = MST.pathToKey(path);

            let mstHandler = MSTHandler.Handler(repo.nodes);

            // Get the current commit to find the MST root
            let ?currentCommit = PureMap.get(repo.commits, TID.compare, repo.rev) else return null;

            // Get the root MST node from the commit's data field
            let ?rootNode = mstHandler.getNode(currentCommit.data) else return null;

            let ?recordCID = mstHandler.getCID(rootNode, pathKey) else return null;
            let ?value = PureMap.get(repo.records, compareCID, recordCID) else return null;
            ?{
                cid = recordCID;
                value = value;
            };
        };

        public func toStableData() : StableData {
            return {
                repositories = repositories;
            };
        };

        private func createCommit(
            repoId : DID.Plc.DID,
            rev : TID.TID,
            newNodeCID : CID.CID,
            lastNodeCID : ?CID.CID,
        ) : async* Result.Result<Commit.Commit, Text> {

            let unsignedCommit : Commit.UnsignedCommit = {
                did = repoId;
                version = 3; // TODO?
                data = newNodeCID;
                rev = rev;
                prev = lastNodeCID;
            };

            // Sign commit
            switch (await* signCommit(unsignedCommit)) {
                case (#ok(commit)) #ok(commit);
                case (#err(e)) return #err("Failed to sign commit: " # e);
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
