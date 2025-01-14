import Result "mo:base/Result";
import Text "mo:base/Text";
import Iter "mo:base/Iter";
import Char "mo:base/Char";
import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import IterTools "mo:itertools/Iter";
import Sha256 "mo:sha2/Sha256";

module MST {
    public type CID = [Nat8]; // TODO

    public type Tree = {
        hash : CID;
        leftSubTree : ?Tree;
        entries : [TreeEntry];
    };

    public type TreeEntry = {
        leaf : Leaf;
        rightSubTree : ?Tree;
    };

    public type Leaf = {
        key : Text;
        value : CID;
    };

    public type AddError = {
        #invalidKey;
        #keyExists;
    };

    public func get(tree : Tree, key : Text) : ?CID {
        let { expectedIndex; keyMatch } = getNextIndex(tree.entries, key);
        if (keyMatch) {
            // Key found
            return ?tree.entries[expectedIndex].leaf.value;
        };
        if (expectedIndex == 0) {
            // Get from left subtree
            switch (tree.leftSubTree) {
                case (null) return null;
                case (?t) return get(t, key);
            };
        } else {
            // Get from right subtree
            switch (tree.entries[expectedIndex - 1].rightSubTree) {
                case (null) return null;
                case (?t) return get(t, key);
            };
        };
    };

    func getNextIndex(entries : [TreeEntry], key : Text) : {
        expectedIndex : Nat;
        keyMatch : Bool;
    } {
        let ?index = entries.vals()
        |> IterTools.findIndex(_, func(entry : TreeEntry) : Bool = entry.leaf.key >= key) else return {
            expectedIndex = entries.size(); // Expected index is out of bounds
            keyMatch = false;
        };
        {
            expectedIndex = index;
            keyMatch = entries[index].leaf.key == key;
        };
    };

    public func add(tree : Tree, key : Text, value : CID) : Result.Result<Tree, AddError> {
        if (not isValidKey(key)) {
            return #err(#invalidKey);
        };
        let keyHashLeadingZeros = getKeyHashLeadingZeros(key);
        let layer = getLayer(tree);
        let newLeaf : Leaf = { key; value };
        if (keyHashLeadingZeros == layer) {
            let { expectedIndex; keyMatch } = getNextIndex(tree.entries, key);
            if (keyMatch) {
                return #err(#keyExists);
            };

            let treeToLeftOfIndex = if (expectedIndex == 0) {
                tree.leftSubTree;
            } else {
                tree.entries[expectedIndex - 1].rightSubTree;
            };

            switch (treeToLeftOfIndex) {
                case (null) {
                    // If there is no tree to the left of the expected index, add the new leaf to the entries
                    let newEntriesBuffer = Buffer.fromArray<TreeEntry>(tree.entries);
                    newEntriesBuffer.insert(expectedIndex, { leaf = newLeaf; rightSubTree = null });
                    let newEntries = Buffer.toArray(newEntriesBuffer);
                    return #ok(hashTree(tree.leftSubTree, newEntries));
                };
                case (?t) {
                    // If there is a tree to the left of the expected index, split the subtree

                    let (newLeftTree, newEntries) = switch (splitTreeAroundKey(t, key)) {
                        case (#leftOfTree) {

                            (null, newEntries);
                        };
                        case (#rightOfTree) {
                            // Add as last entry
                            (t.leftSubTree, tree.entries);
                        };
                        case (#inBetween((leftTree, rightTree))) {

                            (t.leftSubTree, newEntries);
                        };
                    };

                    return #ok(hashTree(newLeftTree, Buffer.toArray(newEntriesBuffer)));
                };
            }

        } else if (keyHashLeadingZeros < layer) {
            // TODO
        } else {
            // TODO
        };
    };

    func splitTreeAroundKey(tree : Tree, key : Text) : (?Tree, ?Tree) {
        let { expectedIndex; keyMatch } = getNextIndex(tree.entries, key);
        if (expectedIndex == 0) {
            return ;
        };
        if (expectedIndex == tree.entries.size()) {
            return #rightOfTree;
        };
        let entriesBuffer = Buffer.fromArray<TreeEntry>(tree.entries);
        let (leftEntriesBuffer, rightEntriesBuffer) = Buffer.split(entriesBuffer, expectedIndex);
        let leftEntries = Buffer.toArray(leftEntriesBuffer);
        let rightEntries = Buffer.toArray(rightEntriesBuffer);

        #inBetween((hashTree(tree.leftSubTree, leftEntries), hashTree(null, rightEntries)));
    };

    func hashTree(leftSubTree : ?Tree, entries : [TreeEntry]) : Tree {
        // TODO
        let hash = [];
        { hash; leftSubTree; entries };
    };

    public func isValidKey(key : Text) : Bool {
        let split = Text.split(key, #char('/'))
        |> Iter.toArray(_);
        key.size() > 0 and key.size() <= 256 and split.size() == 2 and split[0].size() > 0 and split[1].size() > 0 and isValidKeyChars(split[0]) and isValidKeyChars(split[1]);
    };

    func getLayer(tree : Tree) : Nat {
        let layer = 0;
        if (tree.entries.size() == 0) {
            switch (tree.leftSubTree) {
                case (null) return 0;
                case (?t) return getLayer(t) + 1; // Get the sublayer value and add 1
            };
        };
        for (entry in tree.entries.vals()) {
            return getKeyHashLeadingZeros(entry.leaf.key); // Return the leading zeros of any key (same as layer value)
        };
        layer;
    };

    func isValidKeyChars(key : Text) : Bool {
        // a-zA-Z0-9_\-:.
        key.chars()
        |> IterTools.all(
            _,
            func(v : Char) : Bool {
                let c = Char.toNat32(v);

                (c >= 0x30 and c <= 0x39) // 0-9
                or (c >= 0x41 and c <= 0x5A) // A-Z
                or (c >= 0x61 and c <= 0x7A) // a-z
                or c == 0x2D // -
                or c == 0x3A // :
                or c == 0x2E // .
                or c == 0x5F; // _
            },
        );
    };

    func getKeyHashLeadingZeros(key : Text) : Nat {
        let hash : [Nat8] = key
        |> Text.encodeUtf8(_)
        |> Sha256.fromBlob(#sha256, _)
        |> Blob.toArray(_);
        var leadingZeros = 0;
        label f for (byte in hash.vals()) {
            if (byte < 64) {
                // byte < 0b01XXXXXX
                leadingZeros += 1;
            };
            if (byte < 16) {
                // byte < 0b0000XXXX
                leadingZeros += 1;
            };
            if (byte < 4) {
                // byte < 0b000000XX
                leadingZeros += 1;
            };
            if (byte == 0) {
                // byte == 0b00000000
                leadingZeros += 1;
            } else {
                // Only continue if the byte is zero, to check the next byte for any value
                break f;
            };
        };
        leadingZeros;
    };

};
