import Repository "../Types/Repository";
import DID "mo:did";
import CID "mo:cid";
import TID "mo:tid";
import Array "mo:new-base/Array";

module {
    public type StableData = {
        repositories : [Repository.Repository];
    };

    public class Handler(stableData : StableData) {
        var repositories = stableData.repositories;

        public func getAll() : [Repository.Repository] {
            return repositories;
        };

        public func get(repoId : DID.Plc.DID) : ?Repository.Repository {
            for (repo in repositories.vals()) {
                if (repo.did == repoId) {
                    return ?repo;
                };
            };
            return null;
        };

        public func create(
            plcDid : DID.Plc.DID,
            head : CID.CID,
            rev : TID.TID,
        ) : Repository.Repository {
            let newRepo = {
                did = plcDid;
                head = head;
                rev = rev;
                active = true;
                status = null;
            };
            repositories := Array.concat(repositories, [newRepo]);
            return newRepo;
        };

        public func toStableData() : StableData {
            return {
                repositories = repositories;
            };
        };
    };
};
