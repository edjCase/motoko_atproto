import Repository "../Types/Repository";

module {
    public type StableData = {
        repositories : [Repository.Repository];
    };

    public class Handler(stableData : StableData) {
        let repositories = stableData.repositories;

        public func getAll() : [Repository.Repository] {
            return repositories;
        };

        public func toStableData() : StableData {
            return {
                repositories = repositories;
            };
        };
    };
};
