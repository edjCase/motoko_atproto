import Result "mo:core@1/Result";
import CID "mo:cid@1";
import Blob "mo:core@1/Blob";
import DynamicArray "mo:xtended-collections@0/DynamicArray";
import Text "mo:core@1/Text";
import Sha256 "mo:sha2/Sha256";
import Array "mo:core@1/Array";
import MST "../Types/MST";
import Order "mo:core@1/Order";
import Iter "mo:core@1/Iter";
import Nat "mo:core@1/Nat";
import Nat8 "mo:core@1/Nat8";
import Char "mo:core@1/Char";
import Debug "mo:core@1/Debug";
import CIDBuilder "../CIDBuilder";
import PureMap "mo:core@1/pure/Map";
import Set "mo:core@1/Set";
import Runtime "mo:core@1/Runtime";
import DagCbor "mo:dag-cbor@2";
import DagPb "mo:dag-pb@0";

module {

  public class Handler(nodes_ : PureMap.Map<Text, MST.Node>) {
    var nodes = nodes_;

    public func getCID(node : MST.Node, key : [Nat8]) : ?CID.CID {

      // Search through entries at this level
      for (i in node.entries.keys()) {
        let entry = node.entries[i];
        let entryKey = reconstructKey(node.entries, i);

        // If we found exact key match (simplified approach - no depth check)
        if (compareKeys(key, entryKey) == #equal) {
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
        return #err("Invalid key: " # keyToText(key));
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
          return #err("Key already exists: " # keyToText(key));
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

        let entriesBuffer = DynamicArray.fromArray<MST.TreeEntry>(node.entries);
        entriesBuffer.insert(insertIndex, newEntry);
        let newEntries = DynamicArray.toArray(entriesBuffer);

        // Compress keys
        let compressedEntries = compressKeys(newEntries);

        return #ok({
          node with
          entries = compressedEntries;
        });
      } else {
        // keyDepth != nodeDepth - For now, add to current level to avoid tree corruption
        // This is a simplified approach that keeps all keys in a flat structure
        // A full MST implementation would need more sophisticated layer management
        let newEntry : MST.TreeEntry = {
          prefixLength = 0;
          keySuffix = key;
          valueCID = value;
          subtreeCID = null;
        };

        let entriesBuffer = DynamicArray.fromArray<MST.TreeEntry>(node.entries);
        entriesBuffer.insert(insertIndex, newEntry);
        let newEntries = DynamicArray.toArray(entriesBuffer);

        let compressedEntries = compressKeys(newEntries);

        return #ok({
          node with
          entries = compressedEntries;
        });
      };
    };

    // Helper function to convert key bytes to readable text
    private func keyToText(key : [Nat8]) : Text {
      switch (Text.decodeUtf8(Blob.fromArray(key))) {
        case (?text) text;
        case (null) debug_show (key); // Fallback to debug format if not valid UTF-8
      };
    };

    // Upsert (insert or update) a CID in the MST
    public func upsertCID(
      rootNodeCID : CID.CID,
      key : [Nat8],
      value : CID.CID,
    ) : Result.Result<MST.Node, Text> {
      if (key.size() == 0) {
        return #err("Key cannot be empty");
      };

      if (not isValidKey(key)) {
        return #err("Invalid key: " # keyToText(key));
      };
      let ?node = getNode(rootNodeCID) else return #err("Node not found: " # CID.toText(rootNodeCID));
      let keyDepth = calculateDepth(key);

      // Find insertion/update point
      var insertIndex = 0;
      var updateIndex : ?Nat = null;

      label f for (i in node.entries.keys()) {
        let entryKey = reconstructKey(node.entries, i);
        let comparison = compareKeys(key, entryKey);

        if (comparison == #equal) {
          // Key exists, we'll update it
          updateIndex := ?i;
          break f;
        } else if (comparison == #less) {
          insertIndex := i;
          break f;
        } else {
          insertIndex := i + 1;
        };
      };

      switch (updateIndex) {
        case (?idx) {
          // Update existing entry
          let entriesBuffer = DynamicArray.fromArray<MST.TreeEntry>(node.entries);
          let existingEntry = entriesBuffer.get(idx);
          let updatedEntry : MST.TreeEntry = {
            existingEntry with
            valueCID = value;
          };
          entriesBuffer.put(idx, updatedEntry);
          let newEntries = DynamicArray.toArray(entriesBuffer);

          return #ok({
            node with
            entries = newEntries;
          });
        };
        case (null) {
          // Insert new entry (same logic as addCID)
          let nodeDepth = if (node.entries.size() > 0) {
            calculateDepth(reconstructKey(node.entries, 0));
          } else {
            keyDepth;
          };

          if (keyDepth == nodeDepth) {
            let newEntry : MST.TreeEntry = {
              prefixLength = 0;
              keySuffix = key;
              valueCID = value;
              subtreeCID = null;
            };

            let entriesBuffer = DynamicArray.fromArray<MST.TreeEntry>(node.entries);
            entriesBuffer.insert(insertIndex, newEntry);
            let newEntries = DynamicArray.toArray(entriesBuffer);

            let compressedEntries = compressKeys(newEntries);

            return #ok({
              node with
              entries = compressedEntries;
            });
          } else {
            // Simplified approach: add to current level
            let newEntry : MST.TreeEntry = {
              prefixLength = 0;
              keySuffix = key;
              valueCID = value;
              subtreeCID = null;
            };

            let entriesBuffer = DynamicArray.fromArray<MST.TreeEntry>(node.entries);
            entriesBuffer.insert(insertIndex, newEntry);
            let newEntries = DynamicArray.toArray(entriesBuffer);

            let compressedEntries = compressKeys(newEntries);

            return #ok({
              node with
              entries = compressedEntries;
            });
          };
        };
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
        return #err("Invalid key: " # keyToText(key));
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
          let entriesBuffer = DynamicArray.fromArray<MST.TreeEntry>(node.entries);
          let _ = entriesBuffer.remove(i);
          let newEntries = DynamicArray.toArray(entriesBuffer);

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
                      subtreeCID = ?newRightCID;
                    };
                    let entriesBuffer = DynamicArray.fromArray<MST.TreeEntry>(node.entries);
                    entriesBuffer.put(i - 1, updatedEntry);

                    #ok({
                      node with
                      entries = DynamicArray.toArray(entriesBuffer);
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
                subtreeCID = ?newRightCID;
              };
              let entriesBuffer = DynamicArray.fromArray<MST.TreeEntry>(node.entries);
              entriesBuffer.put(lastIndex, updatedEntry);

              #ok({
                node with
                entries = DynamicArray.toArray(entriesBuffer);
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

    public func getAllCollections(rootNode : MST.Node) : [Text] {
      let collectionSet = Set.empty<Text>();

      iterateNodeEntries(
        rootNode,
        func(entryKey : Text, _ : CID.CID) {
          let parts = Text.split(entryKey, #char('/'));
          let partsArray = Iter.toArray(parts);

          // Only consider entries with valid collection format
          if (partsArray.size() == 2) {
            Set.add(collectionSet, Text.compare, partsArray[0]);
          };
        },
      );
      Array.fromIter(Set.values(collectionSet));
    };

    public func getCollectionRecords(rootNode : MST.Node, collection : Text) : [(key : Text, CID.CID)] {
      let records = DynamicArray.DynamicArray<(key : Text, CID.CID)>(0);

      iterateNodeEntries(
        rootNode,
        func(entryKey : Text, entryValue : CID.CID) {
          let parts = Text.split(entryKey, #char('/'));
          let partsArray = Iter.toArray(parts);

          // Check if this entry belongs to the requested collection
          if (partsArray.size() == 2 and partsArray[0] == collection) {
            records.add((partsArray[1], entryValue));
          };
        },
      );

      DynamicArray.toArray(records);
    };

    public func getAllRecordCIDs(rootNode : MST.Node) : [CID.CID] {
      let cids = DynamicArray.DynamicArray<CID.CID>(0);

      iterateNodeEntries(
        rootNode,
        func(_ : Text, entryValue : CID.CID) {
          cids.add(entryValue);
        },
      );

      DynamicArray.toArray(cids);
    };

    private func iterateNodeEntries(
      rootNode : MST.Node,
      callback : (entryKey : Text, entryValue : CID.CID) -> (),
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

      // Start traversal from the specific root node
      traverseNode(rootNode, []);
    };

  };

  public func fromBlockMap(
    rootCID : CID.CID,
    blockMap : PureMap.Map<CID.CID, Blob>,
  ) : Result.Result<Handler, Text> {
    let mstHandler = Handler(PureMap.empty<Text, MST.Node>());
    switch (loadNodeFromBlocks(mstHandler, rootCID, blockMap)) {
      case (#err(e)) #err(e);
      case (#ok) #ok(mstHandler);
    };
  };

  private func loadNodeFromBlocks(
    mstHandler : Handler,
    nodeCID : CID.CID,
    blockMap : PureMap.Map<CID.CID, Blob>,
  ) : Result.Result<(), Text> {
    // Check if node already loaded
    switch (mstHandler.getNode(nodeCID)) {
      case (?_) return #ok;
      case (null) ();
    };

    // Get block data
    let ?blockData = PureMap.get(blockMap, CIDBuilder.compare, nodeCID) else {
      return #err("MST node block not found: " # CID.toText(nodeCID));
    };

    let nodeCodec = switch (nodeCID) {
      case (#v0(_)) #dagPb;
      case (#v1(cidV1)) cidV1.codec;
    };
    let node : MST.Node = switch (nodeCodec) {
      case (#dagCbor) switch (DagCbor.fromBytes(blockData.vals())) {
        case (#ok(value)) {
          switch (parseMSTNodeFromCbor(value)) {
            case (#ok(n)) n;
            case (#err(e)) return #err("Failed to parse MST node: " # e);
          };
        };
        case (#err(e)) return #err("Failed to decode MST node CBOR: " # debug_show (e));
      };
      case (#dagPb) switch (DagPb.fromBytes(blockData.vals())) {
        case (#ok(value)) {
          switch (parseMSTNodeFromPb(value)) {
            case (#ok(n)) n;
            case (#err(e)) return #err("Failed to parse MST node: " # e);
          };
        };
        case (#err(e)) return #err("Failed to decode MST node Protobuf: " # debug_show (e));
      };
      case (codec) return #err(debug_show (codec) # " codec not supported for MST nodes");
    };

    // Recursively load left subtree
    switch (node.leftSubtreeCID) {
      case (?leftCID) {
        switch (loadNodeFromBlocks(mstHandler, leftCID, blockMap)) {
          case (#err(e)) return #err(e);
          case (#ok(_)) ();
        };
      };
      case (null) ();
    };

    // Recursively load subtrees referenced in entries
    for (entry in node.entries.vals()) {
      switch (entry.subtreeCID) {
        case (?subtreeCID) {
          switch (loadNodeFromBlocks(mstHandler, subtreeCID, blockMap)) {
            case (#err(e)) return #err(e);
            case (#ok(_)) ();
          };
        };
        case (null) ();
      };
    };

    // Store this node
    ignore mstHandler.addNode(node);
    #ok;
  };

  private func parseMSTNodeFromCbor(value : DagCbor.Value) : Result.Result<MST.Node, Text> {
    switch (value) {
      case (#map(fields)) {
        var leftSubtreeCID : ?CID.CID = null;
        var entries : [MST.TreeEntry] = [];

        for ((key, val) in fields.vals()) {
          switch (key, val) {
            case ("l", #cid(cid)) leftSubtreeCID := ?cid;
            case ("e", #array(entryArray)) {
              let entriesBuffer = DynamicArray.DynamicArray<MST.TreeEntry>(entryArray.size());

              for (entryVal in entryArray.vals()) {
                switch (parseTreeEntryFromCbor(entryVal)) {
                  case (#ok(entry)) entriesBuffer.add(entry);
                  case (#err(e)) return #err("Failed to parse tree entry: " # e);
                };
              };

              entries := DynamicArray.toArray(entriesBuffer);
            };
            case (_) ();
          };
        };

        #ok({
          leftSubtreeCID = leftSubtreeCID;
          entries = entries;
        });
      };
      case (_) #err("MST node must be a CBOR map");
    };
  };

  private func parseMSTNodeFromPb(value : DagPb.Node) : Result.Result<MST.Node, Text> {
    Runtime.trap("MST Protobuf parsing not implemented yet: " # debug_show (value));
  };

  private func parseTreeEntryFromCbor(value : DagCbor.Value) : Result.Result<MST.TreeEntry, Text> {
    switch (value) {
      case (#map(fields)) {
        var prefixLength : Nat = 0;
        var keySuffix : [Nat8] = [];
        var valueCID : ?CID.CID = null;
        var subtreeCID : ?CID.CID = null;

        for ((key, val) in fields.vals()) {
          switch (key, val) {
            case ("p", #int(p)) prefixLength := Nat.fromInt(p);
            case ("k", #bytes(k)) keySuffix := k;
            case ("v", #cid(cid)) valueCID := ?cid;
            case ("t", #cid(cid)) subtreeCID := ?cid;
            case _ ();
          };
        };

        let ?vCID = valueCID else return #err("Missing value CID in tree entry");

        #ok({
          prefixLength = prefixLength;
          keySuffix = keySuffix;
          valueCID = vCID;
          subtreeCID = subtreeCID;
        });
      };
      case (_) #err("Tree entry must be a CBOR map");
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

    var leadingZeros = 0;

    // Count leading zeros in 2-bit chunks following ATProto specification exactly
    // This matches the leadingZerosOnHash function in ATProto
    label f for (byte in hash.vals()) {
      // Count 2-bit chunks of leading zeros in this byte
      if (byte < 64) { leadingZeros += 1 }; // First 2 bits are 00 (< 0b01000000)
      if (byte < 16) { leadingZeros += 1 }; // First 4 bits are 0000 (< 0b00010000)
      if (byte < 4) { leadingZeros += 1 }; // First 6 bits are 000000 (< 0b00000100)
      if (byte == 0) {
        leadingZeros += 1; // All 8 bits are 0 (== 0b00000000)
      } else {
        // Stop at first non-zero byte - this is the key difference from the buggy version
        break f;
      };
    };

    leadingZeros;
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

    (
      recordKey.chars()
      |> Iter.all(_, isValidChar)
    ) and (
      collection.chars()
      |> Iter.all(_, isValidChar)
    );
  };

  // Reconstruct full key from compressed entries
  private func reconstructKey(entries : [MST.TreeEntry], index : Nat) : [Nat8] {
    if (index >= entries.size()) {
      return [];
    };

    if (index == 0) {
      return entries[0].keySuffix; // First entry has full key
    };

    let entry = entries[index];
    let prefixLen = entry.prefixLength;

    if (prefixLen == 0) {
      return entry.keySuffix; // No compression
    };

    let prevKey = reconstructKey(entries, index - 1);

    if (prefixLen > prevKey.size()) {
      return entry.keySuffix; // Fallback to suffix only
    };

    let prefix = Array.sliceToArray<Nat8>(prevKey, 0, prefixLen);
    Array.concat(prefix, entry.keySuffix);
  };

  // Compress keys by removing common prefixes
  private func compressKeys(entries : [MST.TreeEntry]) : [MST.TreeEntry] {
    if (entries.size() <= 1) {
      // Ensure single entry has prefixLength = 0
      if (entries.size() == 1) {
        return [{
          entries[0] with
          prefixLength = 0;
          keySuffix = reconstructKey(entries, 0);
        }];
      };
      return entries;
    };

    // First, reconstruct all full keys from input entries
    let fullKeys = Array.tabulate<[Nat8]>(entries.size(), func(i) = reconstructKey(entries, i));

    let compressed = DynamicArray.DynamicArray<MST.TreeEntry>(entries.size());

    // First entry keeps full key
    compressed.add({
      entries[0] with
      prefixLength = 0;
      keySuffix = fullKeys[0];
    });

    // Subsequent entries get compressed
    var i = 1;
    while (i < entries.size()) {
      let prevKey = fullKeys[i - 1];
      let currentKey = fullKeys[i];
      let prefixLen = commonPrefixLength(prevKey, currentKey);

      let suffix : [Nat8] = if (prefixLen < currentKey.size()) {
        let suffixLength : Nat = currentKey.size() - prefixLen;
        Array.tabulate<Nat8>(suffixLength, func(j) = currentKey[prefixLen + j]);
      } else {
        [];
      };

      compressed.add({
        entries[i] with
        prefixLength = prefixLen;
        keySuffix = suffix;
      });

      i += 1;
    };

    DynamicArray.toArray(compressed);
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
