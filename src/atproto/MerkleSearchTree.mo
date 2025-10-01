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

  public func empty() : MerkleSearchTree {
    let emptyNode : MerkleNode.Node = {
      leftSubtreeCID = null;
      entries = [];
    };

    let rootCID = CIDBuilder.fromMSTNode(emptyNode);

    {
      root = rootCID;
      nodes = PureMap.add(
        PureMap.empty<CID.CID, MerkleNode.Node>(),
        CIDBuilder.compare,
        rootCID,
        emptyNode,
      );
    };
  };

  public func validate(mst : MerkleSearchTree) : Result.Result<(), Text> {
    let rootNode = getRootNode(mst);
    validateNode(mst, rootNode, null);
  };

  public func get(
    mst : MerkleSearchTree,
    key : Text,
  ) : ?CID.CID {
    let node = getRootNode(mst);
    let keyBytes = keyToBytes(key);
    getRecursive(mst, node, keyBytes, calculateDepth(keyBytes));
  };

  public func add(
    mst : MerkleSearchTree,
    key : Text,
    value : CID.CID,
  ) : Result.Result<MerkleSearchTree, Text> {
    let keyBytes = keyToBytes(key);
    if (keyBytes.size() == 0) return #err("Key cannot be empty");
    if (keyBytes.size() > 256) return #err("Key too long (max 256 bytes)");
    if (not isValidKey(keyBytes)) return #err("Invalid key format");

    let node = getRootNode(mst);
    addRecursive(mst, node, mst.root, keyBytes, value, calculateDepth(keyBytes));
  };

  // Remove a key
  public func remove(
    mst : MerkleSearchTree,
    key : Text,
  ) : Result.Result<MerkleSearchTree, Text> {
    let keyBytes = keyToBytes(key);
    if (keyBytes.size() == 0) return #err("Key cannot be empty");
    if (not isValidKey(keyBytes)) return #err("Invalid key format");

    let node = getRootNode(mst);
    removeRecursive(mst, node, mst.root, keyBytes, calculateDepth(keyBytes));
  };

  // Batch add multiple key-value pairs
  public func addMany(
    mst : MerkleSearchTree,
    items : Iter.Iter<(Text, CID.CID)>,
  ) : Result.Result<MerkleSearchTree, Text> {
    var currentMst = mst;

    for ((keyText, valueCID) in items) {
      switch (add(currentMst, keyText, valueCID)) {
        case (#ok(newMst)) currentMst := newMst;
        case (#err(e)) return #err("Batch add failed at " # keyText # ": " # e);
      };
    };

    #ok(currentMst);
  };

  public func removeMany(
    mst : MerkleSearchTree,
    keys : Iter.Iter<Text>,
  ) : Result.Result<MerkleSearchTree, Text> {
    var currentMst = mst;

    for (keyText in keys) {
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
    let keys = List.empty<Text>();

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
      mst,
      rootNode,
      func(key : [Nat8], value : CID.CID) {
        switch (keyToText(key)) {
          case (?keyText) onEntry(keyText, value);
          case (null) {};
        };
      },
    );
  };
  public func fromBlockMap(
    rootCID : CID.CID,
    blockMap : PureMap.Map<CID.CID, Blob>,
  ) : Result.Result<MerkleSearchTree, Text> {

    // Recursively load all nodes starting from root
    let emptyMap = PureMap.empty<CID.CID, MerkleNode.Node>();
    switch (loadNodeRecursive(rootCID, blockMap, emptyMap)) {
      case (#ok(nodes)) {
        let mst = {
          root = rootCID;
          nodes = nodes;
        };

        // Validate the loaded tree
        switch (validate(mst)) {
          case (#ok(_)) #ok(mst);
          case (#err(e)) #err("Tree validation failed: " # e);
        };
      };
      case (#err(e)) #err(e);
    };
  };

  public func toDebugText(mst : MerkleSearchTree) : Text {
    let buffer = List.empty<Text>();
    let rootNode = getRootNode(mst);

    debugNodeRecursive(mst, rootNode, mst.root, 0, "", buffer);

    Text.join("\n", List.values(buffer));
  };

  private func debugNodeRecursive(
    mst : MerkleSearchTree,
    node : MerkleNode.Node,
    nodeCID : CID.CID,
    depth : Nat,
    prefix : Text,
    buffer : List.List<Text>,
  ) {
    let indent = if (depth == 0) "" else prefix;
    let cidText = CID.toText(nodeCID);

    let keyRange = if (node.entries.size() > 0) {
      let firstKey = reconstructKey(node.entries, 0);
      let lastKey = reconstructKey(node.entries, node.entries.size() - 1);
      switch (keyToText(firstKey), keyToText(lastKey)) {
        case (?first, ?last) " range:" # first # "-" # last;
        case _ "";
      };
    } else {
      " (empty)";
    };

    List.add(
      buffer,
      indent # "[" # cidText # "] keys:" # Nat.toText(node.entries.size()) # keyRange # " depth:" # Nat.toText(depth),
    );

    // Process left subtree
    switch (node.leftSubtreeCID) {
      case (?cid) {
        switch (getNode(mst, cid)) {
          case (?subtree) {
            let newPrefix = if (depth == 0) "├─ " else prefix # "│  ";
            debugNodeRecursive(mst, subtree, cid, depth + 1, newPrefix, buffer);
          };
          case null {};
        };
      };
      case null {};
    };

    // Process entries and their subtrees
    for (i in Nat.range(0, Nat.max(0, node.entries.size()))) {
      let entry = node.entries[i];

      switch (entry.subtreeCID) {
        case (?cid) {
          switch (getNode(mst, cid)) {
            case (?subtree) {
              let isLast = i == node.entries.size() - 1;
              let newPrefix = if (depth == 0) {
                if (isLast) "└─ " else "├─ ";
              } else {
                prefix # (if (isLast) "   " else "│  ");
              };
              debugNodeRecursive(mst, subtree, cid, depth + 1, newPrefix, buffer);
            };
            case null {};
          };
        };
        case null {};
      };
    };
  };

  // PRIVATE HELPER FUNCTIONS

  private func loadNodeRecursive(
    cid : CID.CID,
    blockMap : PureMap.Map<CID.CID, Blob>,
    nodes : PureMap.Map<CID.CID, MerkleNode.Node>,
  ) : Result.Result<PureMap.Map<CID.CID, MerkleNode.Node>, Text> {

    // Check if already loaded
    switch (PureMap.get(nodes, CIDBuilder.compare, cid)) {
      case (?_) return #ok(nodes);
      case null {};
    };

    // Get block data
    let ?blockData = PureMap.get(blockMap, CIDBuilder.compare, cid) else {
      return #err("Block not found: " # CID.toText(cid));
    };

    // Decode CBOR
    let node = switch (DagCbor.fromBytes(blockData.vals())) {
      case (#ok(cbor)) {
        switch (parseMSTNode(cbor)) {
          case (#ok(n)) n;
          case (#err(e)) return #err(e);
        };
      };
      case (#err(e)) return #err("CBOR decode error: " # debug_show (e));
    };

    // Add current node
    var currentNodes = PureMap.add(nodes, CIDBuilder.compare, cid, node);

    // Load left subtree if exists
    switch (node.leftSubtreeCID) {
      case (?leftCID) {
        switch (loadNodeRecursive(leftCID, blockMap, currentNodes)) {
          case (#ok(updated)) currentNodes := updated;
          case (#err(e)) return #err(e);
        };
      };
      case null {};
    };

    // Load entry subtrees
    for (entry in node.entries.vals()) {
      switch (entry.subtreeCID) {
        case (?subtreeCID) {
          switch (loadNodeRecursive(subtreeCID, blockMap, currentNodes)) {
            case (#ok(updated)) currentNodes := updated;
            case (#err(e)) return #err(e);
          };
        };
        case null {};
      };
    };

    #ok(currentNodes);
  };

  private func validateNode(
    mst : MerkleSearchTree,
    node : MerkleNode.Node,
    parentDepth : ?Nat,
  ) : Result.Result<(), Text> {

    // Validate all keys are properly formatted
    for (i in Nat.range(0, Nat.max(0, node.entries.size()))) {
      let key = reconstructKey(node.entries, i);

      if (not isValidKey(key)) {
        return #err("Invalid key format");
      };

      let depth = calculateDepth(key);

      // Check depth consistency - all keys in node should have same depth
      if (i == 0) {
        switch (parentDepth) {
          case (?pd) {
            if (depth >= pd) {
              return #err("Child depth must be less than parent depth");
            };
          };
          case null {};
        };
      } else {
        let prevKey = reconstructKey(node.entries, i - 1);
        let prevDepth = calculateDepth(prevKey);
        if (depth != prevDepth) {
          return #err("All entries in a node must have same depth");
        };
      };
    };

    // Validate entries are sorted
    for (i in Nat.range(1, node.entries.size())) {
      let prevKey = reconstructKey(node.entries, i - 1);
      let currKey = reconstructKey(node.entries, i);

      if (compareKeys(prevKey, currKey) != #less) {
        return #err("Entries must be sorted");
      };
    };

    // Get node depth for child validation
    let nodeDepth = if (node.entries.size() > 0) {
      ?calculateDepth(reconstructKey(node.entries, 0));
    } else {
      null;
    };

    // Validate left subtree
    switch (node.leftSubtreeCID) {
      case (?cid) {
        let ?subtree = getNode(mst, cid) else {
          return #err("Referenced subtree not found");
        };
        switch (validateNode(mst, subtree, nodeDepth)) {
          case (#err(e)) return #err(e);
          case (#ok(_)) {};
        };
      };
      case null {};
    };

    // Validate entry subtrees
    for (entry in node.entries.vals()) {
      switch (entry.subtreeCID) {
        case (?cid) {
          let ?subtree = getNode(mst, cid) else {
            return #err("Referenced subtree not found");
          };
          switch (validateNode(mst, subtree, nodeDepth)) {
            case (#err(e)) return #err(e);
            case (#ok(_)) {};
          };
        };
        case null {};
      };
    };

    #ok(());
  };

  private func addRecursive(
    mst : MerkleSearchTree,
    node : MerkleNode.Node,
    nodeCID : CID.CID,
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
          return insertAtPosition(mst, node, nodeCID, insertPos, key, value, keyDepth);
        };
        case (#greater) insertPos := i + 1;
      };
    };

    // Insert at end or in appropriate position
    insertAtPosition(mst, node, nodeCID, insertPos, key, value, keyDepth);
  };

  private func insertAtPosition(
    mst : MerkleSearchTree,
    node : MerkleNode.Node,
    nodeCID : CID.CID,
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

      let updatedNode = {
        node with
        entries = compressEntries(entries.vals())
      };

      #ok(replaceNode(mst, nodeCID, updatedNode));
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
          let ?subtree = getNode(mst, cid) else return #err("Subtree not found");
          switch (addRecursive(mst, subtree, cid, key, value, keyDepth)) {
            case (#ok(updatedMst)) {
              // updatedMst.root is now the updated subtree's CID
              let newSubtreeCID = updatedMst.root;

              if (pos == 0) {
                let updatedNode = { node with leftSubtreeCID = ?newSubtreeCID };
                #ok(replaceNode(updatedMst, nodeCID, updatedNode));
              } else {
                let entries = Array.tabulate<MerkleNode.TreeEntry>(
                  node.entries.size(),
                  func(i) = if (i == (pos - 1 : Nat)) {
                    { node.entries[i] with subtreeCID = ?newSubtreeCID };
                  } else {
                    node.entries[i];
                  },
                );
                let updatedNode = { node with entries };
                #ok(replaceNode(updatedMst, nodeCID, updatedNode));
              };
            };
            case (#err(e)) #err(e);
          };
        };
        case (null) {
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

          // Add new subtree to MST
          let newSubtreeCID = CIDBuilder.fromMSTNode(newSubtree);
          let mstWithSubtree = {
            root = mst.root;
            nodes = PureMap.add(mst.nodes, CIDBuilder.compare, newSubtreeCID, newSubtree);
          };

          // Update parent to reference new subtree
          if (pos == 0) {
            let updatedNode = { node with leftSubtreeCID = ?newSubtreeCID };
            #ok(replaceNode(mstWithSubtree, nodeCID, updatedNode));
          } else {
            let entries = Array.tabulate<MerkleNode.TreeEntry>(
              node.entries.size(),
              func(i) = if (i == (pos - 1 : Nat)) {
                { node.entries[i] with subtreeCID = ?newSubtreeCID };
              } else {
                node.entries[i];
              },
            );
            let updatedNode = { node with entries };
            #ok(replaceNode(mstWithSubtree, nodeCID, updatedNode));
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

      let entries = DynamicArray.fromArray<MerkleNode.TreeEntry>(node.entries);
      entries.insert(pos, newEntry);

      let updatedNode = {
        node with
        entries = compressEntries(entries.vals())
      };

      #ok(replaceNode(mst, nodeCID, updatedNode));
    };
  };

  private func replaceNode(
    mst : MerkleSearchTree,
    oldCID : CID.CID,
    newNode : MerkleNode.Node,
  ) : MerkleSearchTree {

    // Add new node
    let newCID = CIDBuilder.fromMSTNode(newNode);
    let newNodes = PureMap.add(mst.nodes, CIDBuilder.compare, newCID, newNode);
    // Remove old node
    let (cleanedNodes, _) = PureMap.delete(newNodes, CIDBuilder.compare, oldCID);

    { root = newCID; nodes = cleanedNodes };
  };

  private func getRootNode(mst : MerkleSearchTree) : MerkleNode.Node {
    let ?rootNode = getNode(mst, mst.root) else Runtime.trap("Invalid MST, root node not found");
    rootNode;
  };

  private func getNode(mst : MerkleSearchTree, cid : CID.CID) : ?MerkleNode.Node {
    PureMap.get(mst.nodes, CIDBuilder.compare, cid);
  };

  private func getRecursive(
    mst : MerkleSearchTree,
    node : MerkleNode.Node,
    keyBytes : [Nat8],
    keyDepth : Nat,
  ) : ?CID.CID {
    // Binary search through entries at this level
    var left = 0;
    var right = node.entries.size();

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
    searchSubtree(mst, node, left, keyBytes, keyDepth);
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
          case (?subtree) getRecursive(mst, subtree, key, keyDepth);
          case null null;
        };
      };
      case null null;
    };
  };

  private func removeRecursive(
    mst : MerkleSearchTree,
    node : MerkleNode.Node,
    nodeCID : CID.CID,
    keyBytes : [Nat8],
    keyDepth : Nat,
  ) : Result.Result<MerkleSearchTree, Text> {

    // Find the key in current node
    for (i in Nat.range(0, Nat.max(1, node.entries.size()))) {
      let entryKey = reconstructKey(node.entries, i);
      let entryDepth = calculateDepth(entryKey);

      if (compareKeys(keyBytes, entryKey) == #equal and keyDepth == entryDepth) {
        let entries = DynamicArray.fromArray<MerkleNode.TreeEntry>(node.entries);
        ignore entries.remove(i);

        let newEntries = DynamicArray.toArray(entries);
        let updatedNode = {
          node with
          entries = if (newEntries.size() > 0) compressEntries(newEntries.vals()) else []
        };

        return #ok(replaceNode(mst, nodeCID, updatedNode));
      };
    };

    // Find appropriate subtree
    var searchPos = 0;
    label searchLoop for (i in Nat.range(0, Nat.max(1, node.entries.size()))) {
      let entryKey = reconstructKey(node.entries, i);
      if (compareKeys(keyBytes, entryKey) == #less) {
        searchPos := i;
        break searchLoop;
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

        switch (removeRecursive(mst, subtree, cid, keyBytes, keyDepth)) {
          case (#ok(updatedMst)) {
            let newSubtreeNode = getRootNode(updatedMst);

            // Check if subtree is now empty
            if (newSubtreeNode.entries.size() == 0 and newSubtreeNode.leftSubtreeCID == null) {
              // Remove empty subtree reference
              if (searchPos == 0) {
                let updatedNode = { node with leftSubtreeCID = null };
                return #ok(replaceNode(updatedMst, nodeCID, updatedNode));
              } else {
                let entries = Array.tabulate<MerkleNode.TreeEntry>(
                  node.entries.size(),
                  func(i) = if (i == (searchPos - 1 : Nat)) {
                    { node.entries[i] with subtreeCID = null };
                  } else {
                    node.entries[i];
                  },
                );
                let updatedNode = { node with entries };
                return #ok(replaceNode(updatedMst, nodeCID, updatedNode));
              };
            } else {
              // Update subtree reference
              if (searchPos == 0) {
                let updatedNode = {
                  node with leftSubtreeCID = ?updatedMst.root
                };
                return #ok(replaceNode(updatedMst, nodeCID, updatedNode));
              } else {
                let entries = Array.tabulate<MerkleNode.TreeEntry>(
                  node.entries.size(),
                  func(i) = if (i == (searchPos - 1 : Nat)) {
                    { node.entries[i] with subtreeCID = ?updatedMst.root };
                  } else {
                    node.entries[i];
                  },
                );
                let updatedNode = { node with entries };
                return #ok(replaceNode(updatedMst, nodeCID, updatedNode));
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
          case (?subtree) traverseTreeNode(mst, subtree, callback);
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
    assert (firstEntry.prefixLength == 0);
    List.add(
      compressed,
      {
        firstEntry with
        keySuffix = firstEntry.keySuffix;
      },
    );

    var prevKey = firstEntry.keySuffix;

    // Compress subsequent entries
    for (entry in entries) {
      // Reconstruct the full key from the entry
      let fullKey = if (entry.prefixLength == 0) {
        entry.keySuffix;
      } else {
        let prefix = Array.tabulate<Nat8>(
          Nat.min(entry.prefixLength, prevKey.size()),
          func(i) = prevKey[i],
        );
        Array.concat(prefix, entry.keySuffix);
      };

      // Find common prefix length with previous key
      let prefix = findCommonPrefix(prevKey, fullKey);

      // Extract suffix after common prefix
      let suffix = Array.sliceToArray(fullKey, prefix.size(), fullKey.size());

      List.add(
        compressed,
        {
          entry with
          prefixLength = prefix.size();
          keySuffix = suffix;
        },
      );

      prevKey := fullKey;
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
