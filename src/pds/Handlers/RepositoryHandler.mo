import Repository "../Types/Repository";
import DID "mo:did";

module {
    public type StableData = {
        repositories : [Repository.Repository];
    };

    public class Handler(stableData : StableData) {
        let repositories = stableData.repositories;

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

        public func toStableData() : StableData {
            return {
                repositories = repositories;
            };
        };
    };
};
