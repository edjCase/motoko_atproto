import Result "mo:new-base/Result";
import CID "mo:cid";
import Blob "mo:new-base/Blob";
import Buffer "mo:base/Buffer";
import Text "mo:new-base/Text";
import Sha256 "mo:sha2/Sha256";
import Array "mo:new-base/Array";
import MST "../Types/MST";
import Order "mo:new-base/Order";
import Iter "mo:new-base/Iter";
import Nat "mo:new-base/Nat";
import Nat8 "mo:new-base/Nat8";
import IterTools "mo:itertools/Iter";
import Char "mo:new-base/Char";
import Runtime "mo:new-base/Runtime";
import Debug "mo:new-base/Debug";
import CIDBuilder "../CIDBuilder";
import PureMap "mo:new-base/pure/Map";
import Set "mo:new-base/Set";

module {

    public class Handler(nodes_ : PureMap.Map<Text, MST.Node>) {
        var nodes = nodes_;

        public func getCID(node : MST.Node, key : [Nat8]) : ?CID.CID {
            let keyDepth = calculateDepth(key);

            // Search through entries at this level
            for (i in node.e.keys()) {
                let entry = node.e[i];
                let entryKey = reconstructKey(node.e, i);
                let entryDepth = calculateDepth(entryKey);

                // If we found exact key match and depths match
                if (compareKeys(key, entryKey) == #equal and keyDepth == entryDepth) {
                    return ?entry.v;
                };

                // If key comes before this entry, check left subtree
                if (compareKeys(key, entryKey) == #less) {
                    if (i == 0) {
                        return do ? {
                            let leftCID = node.l!;
                            let leftNode = getNode(leftCID)!;
                            // If left subtree exists, recursively search in it
                            getCID(leftNode, key)!;
                        };
                    } else {
                        // Check right subtree of previous entry
                        return do ? {
                            let rightCID = node.e[i - 1].t!;
                            let rightNode = getNode(rightCID)!;
                            // Recursively search in the loaded right subtree
                            getCID(rightNode, key)!;
                        };
                    };
                };
            };

            // Key is greater than all entries, check rightmost subtree
            if (node.e.size() > 0) {
                do ? {
                    let rightCID = node.e[node.e.size() - 1].t!;
                    let rightNode = getNode(rightCID)!;
                    // Recursively search in the loaded right subtree
                    getCID(rightNode, key)!;
                };
            } else {
                null;
            };
        };

        public func addCID(
            rootNodeCID : CID.CID,
            key : [Nat8],
            value : CID.CID,
        ) : Result.Result<MST.Node, Text> {
            if (key.size() == 0) {
                return #err("Key cannot be empty");
            };

            if (not isValidKey(key)) {
                return #err("Invalid key");
            };
            let ?node = getNode(rootNodeCID) else return #err("Node not found: " # CID.toText(rootNodeCID));
            let keyDepth = calculateDepth(key);

            // Find insertion point
            var insertIndex = 0;
            var found = false;

            label f for (i in node.e.keys()) {
                let entryKey = reconstructKey(node.e, i);
                let comparison = compareKeys(key, entryKey);

                if (comparison == #equal) {
                    return #err("Key already exists: " # debug_show (key));
                } else if (comparison == #less) {
                    insertIndex := i;
                    found := true;
                    break f;
                } else {
                    insertIndex := i + 1;
                };
            };

            // Check if key belongs at this level (same depth as existing entries or empty node)
            let nodeDepth = if (node.e.size() > 0) {
                calculateDepth(reconstructKey(node.e, 0));
            } else {
                keyDepth; // Empty node takes depth of first key
            };

            if (keyDepth == nodeDepth) {
                // Add entry at this level
                let newEntry : MST.TreeEntry = {
                    p = 0; // Will be calculated when compressing
                    k = key;
                    v = value;
                    t = null;
                };

                let entriesBuffer = Buffer.fromArray<MST.TreeEntry>(node.e);
                entriesBuffer.insert(insertIndex, newEntry);
                let newEntries = Buffer.toArray(entriesBuffer);

                // Compress keys
                let compressedEntries = compressKeys(newEntries);

                return #ok({
                    l = node.l;
                    e = compressedEntries;
                });
            } else {
                // Key needs to go in a subtree
                // TODO
                Debug.todo();
            };
        };

        public func removeCID(
            rootNodeCID : CID.CID,
            key : [Nat8],
        ) : Result.Result<MST.Node, Text> {
            if (key.size() == 0) {
                return #err("Key cannot be empty");
            };

            if (not isValidKey(key)) {
                return #err("Invalid key");
            };

            let ?node = getNode(rootNodeCID) else return #err("Node not found: " # CID.toText(rootNodeCID));

            let keyDepth = calculateDepth(key);

            // Search through entries at this level
            for (i in node.e.keys()) {
                let entry = node.e[i];
                let entryKey = reconstructKey(node.e, i);
                let entryDepth = calculateDepth(entryKey);

                // If we found exact key match and depths match
                if (compareKeys(key, entryKey) == #equal and keyDepth == entryDepth) {
                    // Remove this entry
                    let entriesBuffer = Buffer.fromArray<MST.TreeEntry>(node.e);
                    let _ = entriesBuffer.remove(i);
                    let newEntries = Buffer.toArray(entriesBuffer);

                    // Recompress the keys if any entries remain
                    let compressedEntries = if (newEntries.size() > 0) {
                        compressKeys(newEntries);
                    } else {
                        [];
                    };

                    return #ok({
                        l = node.l;
                        e = compressedEntries;
                    });
                };

                // If key comes before this entry, check left subtree
                if (compareKeys(key, entryKey) == #less) {
                    if (i == 0) {
                        // Check left subtree of node
                        return switch (node.l) {
                            case null #err("Key not found: " # debug_show (key));
                            case (?leftCID) {
                                let ?leftNode = getNode(leftCID) else return #err("Left node not found");
                                // Recursively remove from left subtree
                                switch (removeCID(leftCID, key)) {
                                    case (#err(msg)) #err(msg);
                                    case (#ok(updatedLeftNode)) {
                                        // Update the left subtree reference
                                        let newLeftCID = addNode(updatedLeftNode);
                                        #ok({
                                            l = ?newLeftCID;
                                            e = node.e;
                                        });
                                    };
                                };
                            };
                        };
                    } else {
                        // Check right subtree of previous entry
                        return switch (node.e[i - 1].t) {
                            case null #err("Key not found: " # debug_show (key));
                            case (?rightCID) {
                                let ?rightNode = getNode(rightCID) else return #err("Right node not found");
                                // Recursively remove from right subtree
                                switch (removeCID(rightCID, key)) {
                                    case (#err(msg)) #err(msg);
                                    case (#ok(updatedRightNode)) {
                                        // Update the right subtree reference in the entry
                                        let newRightCID = addNode(updatedRightNode);
                                        let updatedEntry = {
                                            node.e[i - 1] with
                                            t = ?newRightCID;
                                        };
                                        let entriesBuffer = Buffer.fromArray<MST.TreeEntry>(node.e);
                                        entriesBuffer.put(i - 1, updatedEntry);

                                        #ok({
                                            l = node.l;
                                            e = Buffer.toArray(entriesBuffer);
                                        });
                                    };
                                };
                            };
                        };
                    };
                };
            };

            // Key is greater than all entries, check rightmost subtree
            if (node.e.size() > 0) {
                let lastIndex = node.e.size() - 1;
                switch (node.e[lastIndex].t) {
                    case null return #err("Key not found: " # debug_show (key));
                    case (?rightCID) {
                        let ?rightNode = getNode(rightCID) else return #err("Right node not found");
                        // Recursively remove from rightmost subtree
                        switch (removeCID(rightCID, key)) {
                            case (#err(msg)) #err(msg);
                            case (#ok(updatedRightNode)) {
                                // Update the rightmost subtree reference
                                let newRightCID = addNode(updatedRightNode);
                                let updatedEntry = {
                                    node.e[lastIndex] with
                                    t = ?newRightCID;
                                };
                                let entriesBuffer = Buffer.fromArray<MST.TreeEntry>(node.e);
                                entriesBuffer.put(lastIndex, updatedEntry);

                                #ok({
                                    l = node.l;
                                    e = Buffer.toArray(entriesBuffer);
                                });
                            };
                        };
                    };
                };
            } else {
                #err("Key not found: " # debug_show (key));
            };
        };

        // Store a node and return its CID
        public func addNode(node : MST.Node) : CID.CID {
            let cid = CIDBuilder.fromMSTNode(node);
            let key = CID.toText(cid);
            nodes := PureMap.add(nodes, Text.compare, key, node);
            cid;
        };

        public func getNode(cid : CID.CID) : ?MST.Node {
            let cidText = CID.toText(cid);
            PureMap.get(nodes, Text.compare, cidText);
        };

        public func getNodes() : PureMap.Map<Text, MST.Node> {
            nodes;
        };

        public func getAllCollections() : [Text] {
            let collectionSet = Set.empty<Text>();
            label f1 for ((_, node) in PureMap.entries(nodes)) {
                label f2 for (entry in node.e.vals()) {
                    // TODO optimize
                    let ?keyText = Text.decodeUtf8(Blob.fromArray(entry.k)) else continue f2;
                    let ?collection = Text.split(keyText, #char('/')).next() else continue f2;
                    Set.add(collectionSet, Text.compare, collection);
                };
            };
            Array.fromIter(Set.values(collectionSet));
        };
    };

    // Compare two byte arrays lexically
    private func compareKeys(a : [Nat8], b : [Nat8]) : Order.Order {
        let minLen = Nat.min(a.size(), b.size());

        for (i in Nat.range(0, minLen)) {
            if (a[i] < b[i]) return #less;
            if (a[i] > b[i]) return #greater;
        };

        if (a.size() < b.size()) return #less;
        if (a.size() > b.size()) return #greater;
        return #equal;
    };

    private func calculateDepth(key : [Nat8]) : Nat {
        let hash = Sha256.fromArray(#sha256, key);

        var depth = 0;

        label f for (byte in hash.vals()) {
            let leadingZeros = countLeadingZeros(byte);
            depth += leadingZeros;

            // Stop if we didn't get all leading zeros in this byte
            if (leadingZeros < 4) {
                break f;
            };
        };

        depth / 2; // Divide by 2 for 2-bit chunks
    };

    // Calculate depth using SHA-256 and 2-bit counting
    // Helper function to count leading zero bits in a byte
    private func countLeadingZeros(byte : Nat8) : Nat {
        if (byte >= 64) return 0; // 0b01000000 - first bit is 1
        if (byte >= 16) return 1; // 0b00010000 - first two bits are 01
        if (byte >= 4) return 2; // 0b00000100 - first three bits are 001
        if (byte >= 1) return 3; // 0b00000001 - first four bits are 0001
        return 4; // 0b00000000 - all bits are 0
    };

    // Validate key format (must be valid repo path)
    private func isValidKey(key : [Nat8]) : Bool {
        if (key.size() == 0 or key.size() > 256) {
            return false;
        };

        // Convert to text for validation
        let keyText = switch (Text.decodeUtf8(Blob.fromArray(key))) {
            case null return false;
            case (?text) text;
        };

        // Check path format: collection/record-key
        let parts = Text.split(keyText, #char('/'));
        let partsArray = Iter.toArray(parts);

        if (partsArray.size() != 2) {
            return false;
        };

        let collection = partsArray[0];
        let recordKey = partsArray[1];

        if (collection.size() == 0 or recordKey.size() == 0) {
            return false;
        };

        // Validate characters (a-zA-Z0-9_\-:.)
        func isValidChar(c : Char) : Bool {
            let code = Char.toNat32(c);
            (code >= 0x30 and code <= 0x39) or // 0-9
            (code >= 0x41 and code <= 0x5A) or // A-Z
            (code >= 0x61 and code <= 0x7A) or // a-z
            code == 0x2D or // -
            code == 0x3A or // :
            code == 0x2E or // .
            code == 0x5F; // _
        };

        let validCollection = keyText.chars() |> IterTools.all(_, isValidChar);
        validCollection;
    };

    // Reconstruct full key from compressed entries
    private func reconstructKey(entries : [MST.TreeEntry], index : Nat) : [Nat8] {
        if (index >= entries.size()) {
            return [];
        };

        if (index == 0) {
            return entries[0].k;
        };

        let prevKey = reconstructKey(entries, index - 1);
        let entry = entries[index];
        let prefixLen = entry.p;

        if (prefixLen > prevKey.size()) {
            return entries[index].k; // Fallback to full key
        };

        let prefix = Array.sliceToArray<Nat8>(prevKey, 0, prefixLen);
        Array.concat(prefix, entry.k);
    };

    // Compress keys by removing common prefixes
    private func compressKeys(entries : [MST.TreeEntry]) : [MST.TreeEntry] {
        if (entries.size() <= 1) {
            return entries;
        };

        let compressed = Buffer.Buffer<MST.TreeEntry>(entries.size());

        // First entry keeps full key
        compressed.add({
            entries[0] with
            p = 0;
        });

        // Subsequent entries get compressed
        for (i in Nat.range(1, entries.size())) {
            let prevKey = reconstructKey(Buffer.toArray(compressed), i - 1);
            let currentKey = entries[i].k;
            let prefixLen = commonPrefixLength(prevKey, currentKey);

            let suffix : [Nat8] = if (prefixLen < currentKey.size()) {
                Array.sliceToArray<Nat8>(currentKey, prefixLen, currentKey.size() - prefixLen);
            } else {
                [];
            };

            compressed.add({
                entries[i] with
                p = prefixLen;
                k = suffix;
            });
        };

        Buffer.toArray(compressed);
    };

    // Calculate common prefix length between two byte arrays
    private func commonPrefixLength(a : [Nat8], b : [Nat8]) : Nat {
        let minLen = Nat.min(a.size(), b.size());
        var prefixLen = 0;

        label f for (i in Nat.range(0, minLen)) {
            if (a[i] == b[i]) {
                prefixLen += 1;
            } else {
                break f;
            };
        };

        prefixLen;
    };
};
