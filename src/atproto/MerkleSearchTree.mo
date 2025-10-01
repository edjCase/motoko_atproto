import Result "mo:core@1/Result";
import CID "mo:cid@1";
import Blob "mo:core@1/Blob";
import DynamicArray "mo:xtended-collections@0/DynamicArray";
import Text "mo:core@1/Text";
import Sha256 "mo:sha2/Sha256";
import Array "mo:core@1/Array";
import Order "mo:core@1/Order";
import Iter "mo:core@1/Iter";
import Nat "mo:core@1/Nat";
import Nat8 "mo:core@1/Nat8";
import Char "mo:core@1/Char";
import Debug "mo:core@1/Debug";
import CIDBuilder "./CIDBuilder";
import PureMap "mo:core@1/pure/Map";
import Set "mo:core@1/Set";
import Runtime "mo:core@1/Runtime";
import DagCbor "mo:dag-cbor@2";
import DagPb "mo:dag-pb@0";
import MerkleNode "MerkleNode";
import Int "mo:core@1/Int";
import List "mo:core@1/List";

module {

  public type MerkleSearchTree = {
    root : CID.CID;
    nodes : PureMap.Map<CID.CID, MerkleNode.Node>;
  };

  public func get(
    mst : MerkleSearchTree,
    key : Text,
  ) : ?CID.CID {
    let node = getRootNode(mst);
    getCIDRecursive(mst, node, key, calculateDepth(mst, key));
  };

  // Add a key-value pair
  public func add(
    mst : MerkleSearchTree,
    key : Text,
    value : CID.CID,
  ) : Result.Result<MerkleSearchTree, Text> {
    if (key.size() == 0) return #err("Key cannot be empty");
    if (key.size() > 256) return #err("Key too long (max 256 bytes)");
    if (not isValidKey(key)) return #err("Invalid key format");

    let ?node = getRootNode(mst);

    addRecursive(mst, node, key, value, calculateDepth(mst, key));
  };

  // Remove a key
  public func remove(
    mst : MerkleSearchTree,
    key : Text,
  ) : Result.Result<MerkleSearchTree, Text> {
    if (key.size() == 0) return #err("Key cannot be empty");
    if (not isValidKey(key)) return #err("Invalid key format");

    let node = getRootNode(mst);

    removeRecursive(mst, node, key, calculateDepth(mst, key));
  };

  // Batch add multiple key-value pairs
  public func batchAdd(
    mst : MerkleSearchTree,
    items : Iter.Iter<(Text, CID.CID)>,
  ) : Result.Result<MerkleSearchTree, Text> {
    var currentMst = mst;

    for ((keyText, valueCID) in items.vals()) {
      let keyBytes = keyToBytes(keyText);
      switch (add(currentMst, keyBytes, valueCID)) {
        case (#ok(newMst)) currentMst := newMst;
        case (#err(e)) return #err("Batch add failed at " # keyText # ": " # e);
      };
    };

    #ok(currentMst);
  };

  // Batch remove multiple keys
  public func batchRemove(
    mst : MerkleSearchTree,
    keys : Iter.Iter<Text>,
  ) : Result.Result<MerkleSearchTree, Text> {
    var currentMst = mst;

    for (keyText in keys.vals()) {
      switch (remove(currentMst, keyText)) {
        case (#ok(newMst)) currentMst := newMst;
        case (#err(e)) return #err("Batch remove failed at " # keyText # ": " # e);
      };
    };

    #ok(currentMst);
  };

  public func listCollections(mst : MerkleSearchTree) : [Text] {
    let collections = Set.empty<Text>();
    traverseTree(
      mst,
      func(key : Text, _ : CID.CID) {
        let parts = Iter.toArray(Text.split(key, #char('/')));
        // TODO how to handle invalid keys here? if size is < 2?
        if (parts.size() >= 2) {
          Set.add(collections, Text.compare, parts[0]);
        };
      },
    );

    Iter.toArray(Set.values(collections));
  };

  public func getAll(mst : MerkleSearchTree) : [CID.CID] {
    let cids = List.empty<CID.CID>();

    traverseTree(
      mst,
      func(_ : Text, entryValue : CID.CID) {
        List.add(cids, entryValue);
      },
    );

    List.toArray(cids);
  };

  public func getByCollection(
    mst : MerkleSearchTree,
    collection : Text,
  ) : [(Text, CID.CID)] {
    let records = List.empty<(Text, CID.CID)>();
    let collectionPrefix = collection # "/";

    // TODO optimize by not visiting entire tree?
    traverseTree(
      mst,
      func(key : Text, value : CID.CID) {
        let rkey = Text.stripStart(key, #text(collectionPrefix));
        switch (rkey) {
          case (?r) List.add(records, (r, value));
          case (null) ();
        };
      },
    );

    List.toArray(records);
  };

  public func getAllKeys(mst : MerkleSearchTree) : [Text] {
    let keys = List.empty<Text>(0);

    traverseTree(
      mst,
      func(key : Text, _ : CID.CID) {
        List.add(keys, key);
      },
    );

    List.toArray(keys);
  };

  public func getTreeDepth(mst : MerkleSearchTree) : Nat {
    let rootNode = getRootNode(mst);
    calculateTreeDepth(mst, rootNode);
  };

  public func traverseTree(
    mst : MerkleSearchTree,
    onEntry : (key : Text, value : CID.CID) -> (),
  ) {
    let rootNode = getRootNode(mst);
    traverseTreeNode(
      rootNode,
      func(key : [Nat8], value : CID.CID) {
        switch (keyToText(key)) {
          case (?keyText) onEntry(keyText, value);
          case (null) {};
        };
      },
    );
  };

  // Create from block map
  public func fromBlockMap(
    rootCID : CID.CID,
    blockMap : PureMap.Map<CID.CID, Blob>,
  ) : Result.Result<MerkleSearchTree, Text> {
    let tree = MerkleSearchTree.empty();

    func loadNode(cid : CID.CID) : Result.Result<(), Text> {
      switch (tree.getNode(cid)) {
        case (?_) #ok(); // Already loaded
        case null {
          let ?blockData = PureMap.get(blockMap, CIDBuilder.compare, cid) else {
            return #err("Block not found: " # CID.toText(cid));
          };

          let node = switch (cid) {
            case (#v0(_)) return #err("CIDv0 not supported");
            case (#v1(v1)) {
              switch (v1.codec) {
                case (#dagCbor) {
                  switch (DagCbor.fromBytes(blockData.vals())) {
                    case (#ok(cbor)) {
                      switch (parseMSTNode(cbor)) {
                        case (#ok(n)) n;
                        case (#err(e)) return #err(e);
                      };
                    };
                    case (#err(e)) return #err("CBOR decode error: " # debug_show (e));
                  };
                };
                case (_) return #err("Only dag-cbor supported");
              };
            };
          };

          // Store node
          ignore tree.addNode(node);

          // Load referenced nodes
          switch (node.leftSubtreeCID) {
            case (?cid) {
              switch (loadNode(cid)) {
                case (#err(e)) return #err(e);
                case (#ok()) {};
              };
            };
            case null {};
          };

          for (entry in node.entries.vals()) {
            switch (entry.subtreeCID) {
              case (?cid) {
                switch (loadNode(cid)) {
                  case (#err(e)) return #err(e);
                  case (#ok()) {};
                };
              };
              case null {};
            };
          };

          #ok();
        };
      };
    };

    switch (loadNode(rootCID)) {
      case (#ok()) #ok(tree);
      case (#err(e)) #err(e);
    };
  };

  // PRIVATE HELPER FUNCTIONS

  private func addNode(mst : MerkleSearchTree, node : MerkleNode.Node) : MerkleSearchTree {
    let newRoot = CIDBuilder.fromMSTNode(node);
    let newnodes = PureMap.add(mst.nodes, compareCid, newRoot, node);
    return { root = newRoot; nodes = newnodes };
  };

  private func getRootNode(mst : MerkleSearchTree) : MerkleNode.Node {
    let ?rootNode = getNode(mst, mst.root) else Runtime.trap("Invalid MST, root node not found");
    rootNode;
  };

  private func getNode(mst : MerkleSearchTree, cid : CID.CID) : ?MerkleNode.Node {
    PureMap.get(mst.nodes, compareCid, cid);
  };

  private func getCIDRecursive(
    mst : MerkleSearchTree,
    node : MerkleNode.Node,
    key : Text,
    keyDepth : Nat,
  ) : ?CID.CID {
    // Binary search through entries at this level
    var left = 0;
    var right = node.entries.size();

    let keyBytes = keyToBytes(key);

    while (left < right) {
      let mid = (left + right) / 2;
      let entryKey = reconstructKey(node.entries, mid);
      let entryDepth = calculateDepth(entryKey);

      switch (compareKeys(keyBytes, entryKey)) {
        case (#equal) {
          // Found exact match - but check depth
          if (keyDepth == entryDepth) {
            return ?node.entries[mid].valueCID;
          } else if (keyDepth < entryDepth) {
            // Key with lower depth would be in subtree
            return searchSubtree(mst, node, mid, keyBytes, keyDepth);
          } else {
            return null // Higher depth key not in tree
          };
        };
        case (#less) right := mid;
        case (#greater) left := mid + 1;
      };
    };

    // Not found at this level, check appropriate subtree
    searchSubtree(mst, node, left, key, keyDepth);
  };

  private func searchSubtree(
    mst : MerkleSearchTree,
    node : MerkleNode.Node,
    index : Nat,
    key : [Nat8],
    keyDepth : Nat,
  ) : ?CID.CID {
    let subtreeCID = if (index == 0) {
      node.leftSubtreeCID;
    } else if (index > node.entries.size()) {
      return null;
    } else {
      node.entries[index - 1].subtreeCID;
    };

    switch (subtreeCID) {
      case (?cid) {
        switch (getNode(mst, cid)) {
          case (?subtree) getCIDRecursive(mst, subtree, key, keyDepth);
          case null null;
        };
      };
      case null null;
    };
  };

  private func addRecursive(
    mst : MerkleSearchTree,
    node : MerkleNode.Node,
    key : [Nat8],
    value : CID.CID,
    keyDepth : Nat,
  ) : Result.Result<MerkleSearchTree, Text> {
    // Find position for new key
    var insertPos = 0;
    var exactMatch = false;

    for (i in Nat.range(0, Nat.max(0, node.entries.size()))) {
      let entryKey = reconstructKey(node.entries, i);
      let entryDepth = calculateDepth(entryKey);

      switch (compareKeys(key, entryKey)) {
        case (#equal) {
          if (keyDepth == entryDepth) {
            return #err("Key already exists");
          };
          exactMatch := true;
          insertPos := i;
        };
        case (#less) {
          insertPos := i;
          return insertAtPosition(node, insertPos, key, value, keyDepth);
        };
        case (#greater) insertPos := i + 1;
      };
    };

    // Insert at end or in appropriate position
    insertAtPosition(node, insertPos, key, value, keyDepth);
  };

  private func insertAtPosition(
    mst : MerkleSearchTree,
    node : MerkleNode.Node,
    pos : Nat,
    key : [Nat8],
    value : CID.CID,
    keyDepth : Nat,
  ) : Result.Result<MerkleSearchTree, Text> {
    // Determine if key belongs at this level
    let nodeDepth = if (node.entries.size() > 0) {
      calculateDepth(reconstructKey(node.entries, 0));
    } else {
      keyDepth // Empty node takes first key's depth
    };

    if (keyDepth == nodeDepth) {
      // Insert at this level
      let newEntry : MerkleNode.TreeEntry = {
        prefixLength = 0; // Will be recalculated
        keySuffix = key;
        valueCID = value;
        subtreeCID = null;
      };

      let entries = DynamicArray.fromArray<MerkleNode.TreeEntry>(node.entries);
      entries.insert(pos, newEntry);

      #ok({
        node with
        entries = compressEntries(DynamicArray.toArray(entries))
      });
    } else if (keyDepth < nodeDepth) {
      // Lower depth - goes in subtree
      let subtreeCID = if (pos == 0) node.leftSubtreeCID else {
        if (pos - 1 < node.entries.size()) {
          node.entries[pos - 1].subtreeCID;
        } else {
          null;
        };
      };

      switch (subtreeCID) {
        case (?cid) {
          // Recursively add to subtree
          let ?subtree = getNode(cid) else return #err("Subtree not found");
          switch (addRecursive(subtree, key, value, keyDepth)) {
            case (#ok(newSubtree)) {
              let newCID = addNode(newSubtree);
              if (pos == 0) {
                #ok({ node with leftSubtreeCID = ?newCID });
              } else {
                let entries = Array.tabulate<MerkleNode.TreeEntry>(
                  node.entries.size(),
                  func(i) = if (i == (pos - 1 : Nat)) {
                    { node.entries[i] with subtreeCID = ?newCID };
                  } else {
                    node.entries[i];
                  },
                );
                #ok({ node with entries });
              };
            };
            case (#err(e)) #err(e);
          };
        };
        case null {
          // Create new subtree
          let newSubtree : MerkleNode.Node = {
            leftSubtreeCID = null;
            entries = [{
              prefixLength = 0;
              keySuffix = key;
              valueCID = value;
              subtreeCID = null;
            }];
          };
          let newCID = addNode(newSubtree);

          if (pos == 0) {
            #ok({ node with leftSubtreeCID = ?newCID });
          } else {
            let entries = Array.tabulate<MerkleNode.TreeEntry>(
              node.entries.size(),
              func(i) = if (i == (pos - 1 : Nat)) {
                { node.entries[i] with subtreeCID = ?newCID };
              } else {
                node.entries[i];
              },
            );
            #ok({ node with entries });
          };
        };
      };
    } else {
      // Higher depth key - needs to split existing structure
      // For simplicity, add at this level for now
      // A full implementation would need proper splitting logic
      let newEntry : MerkleNode.TreeEntry = {
        prefixLength = 0;
        keySuffix = key;
        valueCID = value;
        subtreeCID = null;
      };

      let entries = Buffer.fromArray<MerkleNode.TreeEntry>(node.entries);
      entries.insert(pos, newEntry);

      #ok({
        node with
        entries = compressEntries(Buffer.toArray(entries))
      });
    };
  };

  private func removeRecursive(
    mst : MerkleSearchTree,
    node : MerkleNode.Node,
    key : [Nat8],
    keyDepth : Nat,
  ) : Result.Result<MerkleSearchTree, Text> {
    // Find the key
    for (i in Nat.range(0, Nat.max(0, node.entries.size()))) {
      let entryKey = reconstructKey(node.entries, i);
      let entryDepth = calculateDepth(entryKey);

      if (compareKeys(key, entryKey) == #equal and keyDepth == entryDepth) {
        // Found it - remove from this level
        let entries = DynamicArray.fromArray<MerkleNode.TreeEntry>(node.entries);
        ignore entries.remove(i);

        // Merge subtrees if needed
        let newEntries = DynamicArray.toArray(entries);
        return #ok({
          node with
          entries = if (newEntries.size() > 0) compressEntries(newEntries) else []
        });
      };
    };

    // Not at this level - check subtrees
    var searchPos = 0;
    label f for (i in Nat.range(0, Nat.max(0, node.entries.size()))) {
      let entryKey = reconstructKey(node.entries, i);
      if (compareKeys(key, entryKey) == #less) {
        searchPos := i;
        break f;
      };
      searchPos := i + 1;
    };

    let subtreeCID = if (searchPos == 0) {
      node.leftSubtreeCID;
    } else if ((searchPos - 1 : Nat) < node.entries.size()) {
      node.entries[searchPos - 1].subtreeCID;
    } else {
      null;
    };

    switch (subtreeCID) {
      case (?cid) {
        let ?subtree = getNode(mst, cid) else return #err("Subtree not found");
        switch (removeRecursive(mst, subtree, key, keyDepth)) {
          case (#ok(newSubtree)) {
            // Check if subtree is now empty
            if (newSubtree.entries.size() == 0 and newSubtree.leftSubtreeCID == null) {
              // Remove empty subtree
              if (searchPos == 0) {
                #ok({ node with leftSubtreeCID = null });
              } else {
                let entries = Array.tabulate<MerkleNode.TreeEntry>(
                  node.entries.size(),
                  func(i) = if (i == (searchPos - 1 : Nat)) {
                    { node.entries[i] with subtreeCID = null };
                  } else {
                    node.entries[i];
                  },
                );
                #ok({ node with entries });
              };
            } else {
              // Update subtree reference
              let newMst = addNode(mst, newSubtree);
              if (searchPos == 0) {
                #ok({ node with leftSubtreeCID = ?newMst.root });
              } else {
                let entries = Array.tabulate<MerkleNode.TreeEntry>(
                  node.entries.size(),
                  func(i) = if (i == (searchPos - 1 : Nat)) {
                    { node.entries[i] with subtreeCID = ?newMst.root };
                  } else {
                    node.entries[i];
                  },
                );
                #ok({ node with entries });
              };
            };
          };
          case (#err(e)) #err(e);
        };
      };
      case null #err("Key not found");
    };
  };

  private func traverseTreeNode(
    mst : MerkleSearchTree,
    node : MerkleNode.Node,
    callback : ([Nat8], CID.CID) -> (),
  ) {
    // Process left subtree
    switch (node.leftSubtreeCID) {
      case (?cid) {
        switch (getNode(mst, cid)) {
          case (?subtree) traverseTreeNode(subtree, callback);
          case null {};
        };
      };
      case null {};
    };

    // Process entries
    for (i in Nat.range(0, Nat.max(0, node.entries.size()))) {
      let entry = node.entries[i];
      let key = reconstructKey(node.entries, i);
      callback(key, entry.valueCID);

      // Process right subtree
      switch (entry.subtreeCID) {
        case (?cid) {
          switch (getNode(mst, cid)) {
            case (?subtree) traverseTreeNode(mst, subtree, callback);
            case null {};
          };
        };
        case null {};
      };
    };
  };

  private func calculateTreeDepth(
    mst : MerkleSearchTree,
    node : MerkleNode.Node,
  ) : Nat {
    var maxDepth = 1;

    // Check left subtree
    switch (node.leftSubtreeCID) {
      case (?cid) {
        switch (getNode(mst, cid)) {
          case (?subtree) {
            let depth = 1 + calculateTreeDepth(mst, subtree);
            if (depth > maxDepth) maxDepth := depth;
          };
          case null {};
        };
      };
      case null {};
    };

    // Check entry subtrees
    for (entry in node.entries.vals()) {
      switch (entry.subtreeCID) {
        case (?cid) {
          switch (getNode(mst, cid)) {
            case (?subtree) {
              let depth = 1 + calculateTreeDepth(mst, subtree);
              if (depth > maxDepth) maxDepth := depth;
            };
            case null {};
          };
        };
        case null {};
      };
    };

    maxDepth;
  };

  // Calculate depth using ATProto's 2-bit leading zero counting
  private func calculateDepth(key : [Nat8]) : Nat {
    let hash = Sha256.fromArray(#sha256, key);
    var leadingZeros = 0;

    for (byte in hash.vals()) {
      if (byte == 0) {
        leadingZeros += 4; // All 8 bits = 4 two-bit chunks
      } else if (byte < 4) {
        leadingZeros += 3; // 0b000000xx
        return leadingZeros;
      } else if (byte < 16) {
        leadingZeros += 2; // 0b0000xxxx
        return leadingZeros;
      } else if (byte < 64) {
        leadingZeros += 1; // 0b00xxxxxx
        return leadingZeros;
      } else {
        return leadingZeros; // No leading zeros in this byte
      };
    };

    leadingZeros;
  };

  // Validate key format
  private func isValidKey(key : [Nat8]) : Bool {
    let ?keyText = keyToText(key) else return false;
    let parts = Iter.toArray(Text.split(keyText, #char('/')));

    if (parts.size() != 2) return false;

    let collection = parts[0];
    let rkey = parts[1];

    // Check for empty parts or relative paths
    if (
      collection == "" or rkey == "" or
      collection == "." or collection == ".." or
      rkey == "." or rkey == ".."
    ) {
      return false;
    };

    // Validate characters (A-Za-z0-9.-_~:)
    for (char in keyText.chars()) {
      if (not isValidKeyChar(char) and char != '/') {
        return false;
      };
    };

    true;
  };

  private func isValidKeyChar(c : Char) : Bool {
    (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '.' or c == '-' or c == '_' or c == '~' or c == ':';
  };

  private func keyToText(key : [Nat8]) : ?Text {
    Text.decodeUtf8(Blob.fromArray(key));
  };

  private func keyToBytes(key : Text) : [Nat8] {
    Blob.toArray(Text.encodeUtf8(key));
  };

  private func compareKeys(a : [Nat8], b : [Nat8]) : Order.Order {
    let minLen = Nat.min(a.size(), b.size());

    for (i in Nat.range(0, Nat.max(0, minLen))) {
      if (a[i] < b[i]) return #less;
      if (a[i] > b[i]) return #greater;
    };

    if (a.size() < b.size()) return #less;
    if (a.size() > b.size()) return #greater;
    #equal;
  };

  private func reconstructKey(
    entries : [MerkleNode.TreeEntry],
    index : Nat,
  ) : [Nat8] {
    if (index >= entries.size()) return [];

    if (index == 0) {
      return entries[0].keySuffix;
    };

    let entry = entries[index];
    let prevKey = reconstructKey(entries, index - 1);

    if (entry.prefixLength == 0) {
      return entry.keySuffix;
    };

    if (entry.prefixLength > prevKey.size()) {
      // Defensive: use what we can
      return Array.concat(prevKey, entry.keySuffix);
    };

    let prefix = Array.tabulate<Nat8>(
      entry.prefixLength,
      func(i) = prevKey[i],
    );

    Array.concat(prefix, entry.keySuffix);
  };

  private func compressEntries(entries : Iter.Iter<MerkleNode.TreeEntry>) : [MerkleNode.TreeEntry] {
    let ?firstEntry = entries.next() else return [];

    let compressed = List.empty<MerkleNode.TreeEntry>();

    // First entry always has prefixLength = 0
    List.add(
      compressed,
      {
        firstEntry with
        prefixLength = 0;
        keySuffix = firstEntry.keySuffix;
      },
    );

    var prevKey = firstEntry.keySuffix;

    // Compress subsequent entries
    for (entry in entries) {
      // Find common prefix length
      let prefix = findCommonPrefix(prevKey, entry.keySuffix);

      // Extract suffix after common prefix
      let suffix = Array.sliceToArray(entry.keySuffix, prefix.size(), entry.keySuffix.size());

      List.add(
        compressed,
        {
          entry with
          prefixLength = prefix.size();
          keySuffix = suffix;
        },
      );

      prevKey := entry.keySuffix;
    };

    List.toArray(compressed);
  };

  private func findCommonPrefix(a : [Nat8], b : [Nat8]) : [Nat8] {
    let aChars = a.vals();
    let bChars = b.vals();
    var result = DynamicArray.DynamicArray<Nat8>(Nat.min(a.size(), b.size()));
    label l loop {
      switch (aChars.next(), bChars.next()) {
        case (?ac, ?bc) {
          if (ac == bc) {
            result.add(ac);
          } else {
            break l;
          };
        };
        case _ { break l };
      };
    };
    DynamicArray.toArray(result);
  };

  private func parseMSTNode(value : DagCbor.Value) : Result.Result<MerkleNode.Node, Text> {
    switch (value) {
      case (#map(fields)) {
        var leftSubtreeCID : ?CID.CID = null;
        var entries : [MerkleNode.TreeEntry] = [];

        for ((key, val) in fields.vals()) {
          switch (key, val) {
            case ("l", #cid(cid)) leftSubtreeCID := ?cid;
            case ("e", #array(entryArray)) {
              let entriesBuffer = DynamicArray.DynamicArray<MerkleNode.TreeEntry>(entryArray.size());

              for (entryVal in entryArray.vals()) {
                switch (parseTreeEntry(entryVal)) {
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

  private func parseTreeEntry(value : DagCbor.Value) : Result.Result<MerkleNode.TreeEntry, Text> {
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
};
