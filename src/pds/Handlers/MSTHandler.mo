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
import Debug "mo:new-base/Debug";
import CIDBuilder "../CIDBuilder";
import PureMap "mo:new-base/pure/Map";
import Set "mo:new-base/Set";
import Runtime "mo:new-base/Runtime";

module {

    public class Handler(nodes_ : PureMap.Map<Text, MST.Node>) {
        var nodes = nodes_;

        public func getCID(node : MST.Node, key : [Nat8]) : ?CID.CID {
            let keyDepth = calculateDepth(key);

            // Search through entries at this level
            for (i in node.entries.keys()) {
                let entry = node.entries[i];
                let entryKey = reconstructKey(node.entries, i);
                let entryDepth = calculateDepth(entryKey);

                // If we found exact key match and depths match
                if (compareKeys(key, entryKey) == #equal and keyDepth == entryDepth) {
                    return ?entry.valueCID;
                };

                // If key comes before this entry, check left subtree
                if (compareKeys(key, entryKey) == #less) {
                    if (i == 0) {
                        return do ? {
                            let leftCID = node.leftSubtreeCID!;
                            let leftNode = getNode(leftCID)!;
                            // If left subtree exists, recursively search in it
                            getCID(leftNode, key)!;
                        };
                    } else {
                        // Check right subtree of previous entry
                        return do ? {
                            let rightCID = node.entries[i - 1].subtreeCID!;
                            let rightNode = getNode(rightCID)!;
                            // Recursively search in the loaded right subtree
                            getCID(rightNode, key)!;
                        };
                    };
                };
            };

            // Key is greater than all entries, check rightmost subtree
            if (node.entries.size() > 0) {
                do ? {
                    let rightCID = node.entries[node.entries.size() - 1].subtreeCID!;
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

            label f for (i in node.entries.keys()) {
                let entryKey = reconstructKey(node.entries, i);
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
            let nodeDepth = if (node.entries.size() > 0) {
                calculateDepth(reconstructKey(node.entries, 0));
            } else {
                keyDepth; // Empty node takes depth of first key
            };

            if (keyDepth == nodeDepth) {
                // Add entry at this level
                let newEntry : MST.TreeEntry = {
                    prefixLength = 0; // Will be calculated when compressing
                    keySuffix = key;
                    valueCID = value;
                    subtreeCID = null;
                };

                let entriesBuffer = Buffer.fromArray<MST.TreeEntry>(node.entries);
                entriesBuffer.insert(insertIndex, newEntry);
                let newEntries = Buffer.toArray(entriesBuffer);

                // Compress keys
                let compressedEntries = compressKeys(newEntries);

                return #ok({
                    node with
                    entries = compressedEntries;
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
            for (i in node.entries.keys()) {
                let entryKey = reconstructKey(node.entries, i);
                let entryDepth = calculateDepth(entryKey);

                // If we found exact key match and depths match
                if (compareKeys(key, entryKey) == #equal and keyDepth == entryDepth) {
                    // Remove this entry
                    let entriesBuffer = Buffer.fromArray<MST.TreeEntry>(node.entries);
                    let _ = entriesBuffer.remove(i);
                    let newEntries = Buffer.toArray(entriesBuffer);

                    // Recompress the keys if any entries remain
                    let compressedEntries = if (newEntries.size() > 0) {
                        compressKeys(newEntries);
                    } else {
                        [];
                    };

                    return #ok({
                        node with
                        entries = compressedEntries;
                    });
                };

                // If key comes before this entry, check left subtree
                if (compareKeys(key, entryKey) == #less) {
                    if (i == 0) {
                        // Check left subtree of node
                        return switch (node.leftSubtreeCID) {
                            case null #err("Key not found: " # debug_show (key));
                            case (?leftCID) {
                                let ?_ = getNode(leftCID) else return #err("Left node not found");
                                // Recursively remove from left subtree
                                switch (removeCID(leftCID, key)) {
                                    case (#err(msg)) #err(msg);
                                    case (#ok(updatedLeftNode)) {
                                        // Update the left subtree reference
                                        let newLeftCID = addNode(updatedLeftNode);
                                        #ok({
                                            leftSubtreeCID = ?newLeftCID;
                                            entries = node.entries;
                                        });
                                    };
                                };
                            };
                        };
                    } else {
                        // Check right subtree of previous entry
                        return switch (node.entries[i - 1].subtreeCID) {
                            case null #err("Key not found: " # debug_show (key));
                            case (?rightCID) {
                                let ?_ = getNode(rightCID) else return #err("Right node not found");
                                // Recursively remove from right subtree
                                switch (removeCID(rightCID, key)) {
                                    case (#err(msg)) #err(msg);
                                    case (#ok(updatedRightNode)) {
                                        // Update the right subtree reference in the entry
                                        let newRightCID = addNode(updatedRightNode);
                                        let updatedEntry = {
                                            node.entries[i - 1] with
                                            t = ?newRightCID;
                                        };
                                        let entriesBuffer = Buffer.fromArray<MST.TreeEntry>(node.entries);
                                        entriesBuffer.put(i - 1, updatedEntry);

                                        #ok({
                                            node with
                                            entries = Buffer.toArray(entriesBuffer);
                                        });
                                    };
                                };
                            };
                        };
                    };
                };
            };

            if (node.entries.size() <= 0) return #err("Key not found: " # debug_show (key));

            // Key is greater than all entries, check rightmost subtree
            let lastIndex : Nat = node.entries.size() - 1;
            switch (node.entries[lastIndex].subtreeCID) {
                case null return #err("Key not found: " # debug_show (key));
                case (?rightCID) {
                    let ?_ = getNode(rightCID) else return #err("Right node not found");
                    // Recursively remove from rightmost subtree
                    switch (removeCID(rightCID, key)) {
                        case (#err(msg)) #err(msg);
                        case (#ok(updatedRightNode)) {
                            // Update the rightmost subtree reference
                            let newRightCID = addNode(updatedRightNode);
                            let updatedEntry = {
                                node.entries[lastIndex] with
                                t = ?newRightCID;
                            };
                            let entriesBuffer = Buffer.fromArray<MST.TreeEntry>(node.entries);
                            entriesBuffer.put(lastIndex, updatedEntry);

                            #ok({
                                node with
                                entries = Buffer.toArray(entriesBuffer);
                            });
                        };
                    };
                };
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

            iterateEntries(
                func(entryKey : Text, _ : CID.CID) {
                    let parts = Text.split(entryKey, #char('/'));
                    let partsArray = Iter.toArray(parts);

                    // Only consider entries with valid collection format
                    if (partsArray.size() == 2) {
                        Set.add(collectionSet, Text.compare, partsArray[0]);
                    };
                }
            );
            Array.fromIter(Set.values(collectionSet));
        };

        public func getCollectionRecords(collection : Text) : [(key : Text, CID.CID)] {
            let records = Buffer.Buffer<(key : Text, CID.CID)>(0);

            iterateEntries(
                func(entryKey : Text, entryValue : CID.CID) {
                    let parts = Text.split(entryKey, #char('/'));
                    let partsArray = Iter.toArray(parts);

                    // Check if this entry belongs to the requested collection
                    if (partsArray.size() == 2 and partsArray[0] == collection) {
                        records.add((partsArray[1], entryValue));
                    };
                }
            );

            Buffer.toArray(records);
        };

        private func iterateEntries(
            callback : (entryKey : Text, entryValue : CID.CID) -> ()
        ) : () {
            // Helper function to traverse a node and its subtrees
            func traverseNode(node : MST.Node, keyPrefix : [Nat8]) : () {
                // Process left subtree first
                switch (node.leftSubtreeCID) {
                    case (?leftCID) {
                        switch (getNode(leftCID)) {
                            case (?leftNode) traverseNode(leftNode, keyPrefix);
                            case null {};
                        };
                    };
                    case null {};
                };

                // Process entries in this node
                for (i in node.entries.keys()) {
                    let entry = node.entries[i];

                    // Reconstruct full key for this entry
                    let fullKey = if (i == 0) {
                        Array.concat(keyPrefix, entry.keySuffix);
                    } else {
                        // Use prefix compression
                        let prevEntryKey = reconstructKey(node.entries, i - 1);
                        let prevFullKey = Array.concat(keyPrefix, prevEntryKey);

                        let prefixLen = entry.prefixLength;
                        let prefix = if (prefixLen > prevFullKey.size()) {
                            prevFullKey;
                        } else {
                            Array.sliceToArray<Nat8>(prevFullKey, 0, prefixLen);
                        };
                        Array.concat(prefix, entry.keySuffix);
                    };

                    // Convert to text and call callback
                    switch (Text.decodeUtf8(Blob.fromArray(fullKey))) {
                        case (?keyText) callback(keyText, entry.valueCID);
                        case (null) Runtime.trap("Invalid UTF-8 in key: " # debug_show (fullKey));
                    };

                    // Process right subtree of this entry
                    switch (entry.subtreeCID) {
                        case (?rightCID) {
                            switch (getNode(rightCID)) {
                                case (?rightNode) traverseNode(rightNode, fullKey);
                                case (null) {};
                            };
                        };
                        case (null) {};
                    };
                };
            };

            // Start traversal from all root nodes
            for ((_, rootNode) in PureMap.entries(nodes)) {
                traverseNode(rootNode, []);
            };
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
            return entries[0].keySuffix; // First entry has full key
        };

        let prevKey = reconstructKey(entries, index - 1);
        let entry = entries[index];
        let prefixLen = entry.prefixLength;

        if (prefixLen > prevKey.size()) {
            return entries[index].keySuffix; // Fallback to full key
        };

        let prefix = Array.sliceToArray<Nat8>(prevKey, 0, prefixLen);
        Array.concat(prefix, entry.keySuffix);
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
            prefixLength = 0;
        });

        // Subsequent entries get compressed
        for (i in Nat.range(1, entries.size())) {
            let prevKey = reconstructKey(Buffer.toArray(compressed), i - 1);
            let currentKey = entries[i].keySuffix;
            let prefixLen = commonPrefixLength(prevKey, currentKey);

            let suffix : [Nat8] = if (prefixLen < currentKey.size()) {
                Array.sliceToArray<Nat8>(currentKey, prefixLen, currentKey.size() - prefixLen);
            } else {
                [];
            };

            compressed.add({
                entries[i] with
                prefixLength = prefixLen;
                keySuffix = suffix;
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
