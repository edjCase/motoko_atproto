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
import CIDBuilder "./CIDBuilder";
import PureMap "mo:core@1/pure/Map";
import Runtime "mo:core@1/Runtime";
import DagCbor "mo:dag-cbor@2";
import MerkleNode "MerkleNode";
import List "mo:core@1/List";
import Set "mo:core@1/Set";

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

  public func size(mst : MerkleSearchTree) : Nat {
    var count = 0;
    traverseTree(
      mst,
      func(key : Text, value : CID.CID) {
        count += 1;
      },
    );
    count;
  };

  public func get(
    mst : MerkleSearchTree,
    key : Text,
  ) : ?CID.CID {
    let node = getRootNode(mst);
    let keyBytes = keyToBytes(key);
    getRecursive(mst, node, keyBytes);
  };

  public func add(
    mst : MerkleSearchTree,
    key : Text,
    value : CID.CID,
  ) : Result.Result<MerkleSearchTree, Text> {
    addOrUpdateInternal(mst, key, value, true);
  };

  public func put(
    mst : MerkleSearchTree,
    key : Text,
    value : CID.CID,
  ) : Result.Result<MerkleSearchTree, Text> {
    addOrUpdateInternal(mst, key, value, false);
  };

  public func remove(
    mst : MerkleSearchTree,
    key : Text,
  ) : Result.Result<(MerkleSearchTree, CID.CID), Text> {
    let keyBytes = keyToBytes(key);
    if (keyBytes.size() == 0) return #err("Key cannot be empty");

    let node = getRootNode(mst);
    removeRecursive(mst, node, mst.root, keyBytes);
  };

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
  ) : Result.Result<(MerkleSearchTree, [CID.CID]), Text> {
    var currentMst = mst;
    let removedCids = List.empty<CID.CID>();

    for (keyText in keys) {
      switch (remove(currentMst, keyText)) {
        case (#ok((newMst, removedValue))) {
          currentMst := newMst;
          List.add(removedCids, removedValue);
        };
        case (#err(e)) return #err("Batch remove failed at " # keyText # ": " # e);
      };
    };

    #ok((currentMst, List.toArray(removedCids)));
  };

  public func entries(mst : MerkleSearchTree) : Iter.Iter<(Text, CID.CID)> {
    // TODO optimize by not creating list?
    let records = List.empty<(Text, CID.CID)>();

    traverseTree(
      mst,
      func(key : Text, value : CID.CID) {
        List.add(records, (key, value));
      },
    );

    List.values(records);
  };

  public func nodes(mst : MerkleSearchTree) : Iter.Iter<(CID.CID, MerkleNode.Node)> {
    let rootNode = getRootNode(mst);
    let nodeList = List.empty<(CID.CID, MerkleNode.Node)>();
    nodesInternal(
      mst,
      rootNode,
      func(nodeId : CID.CID, node : MerkleNode.Node) {
        List.add(nodeList, (nodeId, node));
      },
    );
    List.values(nodeList);
  };

  public func nodesSince(mst : MerkleSearchTree, previousRoot : CID.CID) : Iter.Iter<(CID.CID, MerkleNode.Node)> {
    let previousNodes = nodes({
      root = previousRoot;
      nodes = mst.nodes;
    });
    let previousNodeIds = previousNodes
    |> Iter.map(
      _,
      func((cid, _) : (CID.CID, MerkleNode.Node)) : CID.CID = cid,
    )
    |> Set.fromIter(_, CIDBuilder.compare);

    nodes(mst)
    |> Iter.filter(
      _,
      func((cid, _) : (CID.CID, MerkleNode.Node)) : Bool = not Set.contains(previousNodeIds, CIDBuilder.compare, cid),
    );

  };

  private func nodesInternal(
    mst : MerkleSearchTree,
    node : MerkleNode.Node,
    callback : (nodeId : CID.CID, node : MerkleNode.Node) -> (),
  ) {
    // Process left subtree
    switch (node.leftSubtreeCID) {
      case (?cid) {
        switch (getNode(mst, cid)) {
          case (?subtree) nodesInternal(mst, subtree, callback);
          case (null) {};
        };
      };
      case (null) {};
    };

    for (entry in node.entries.vals()) {
      switch (entry.subtreeCID) {
        case (?cid) {
          switch (getNode(mst, cid)) {
            case (?subtree) nodesInternal(mst, subtree, callback);
            case (null) {};
          };
        };
        case (null) {};
      };
    };
  };

  public func keys(mst : MerkleSearchTree) : Iter.Iter<Text> {
    // TODO optimize by not creating list?
    let keys = List.empty<Text>();

    traverseTree(
      mst,
      func(key : Text, value : CID.CID) {
        List.add(keys, key);
      },
    );

    List.values(keys);
  };

  public func values(mst : MerkleSearchTree) : Iter.Iter<CID.CID> {
    // TODO optimize by not creating list?
    let values = List.empty<CID.CID>();

    traverseTree(
      mst,
      func(key : Text, value : CID.CID) {
        List.add(values, value);
      },
    );

    List.values(values);
  };

  public func getTreeDepth(mst : MerkleSearchTree) : Nat {
    let rootNode = getRootNode(mst);
    calculateTreeDepth(mst, rootNode);
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

  private func traverseTree(
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
      let firstKey = reconstructKey(node.entries, 0, null);
      let lastKey = reconstructKey(node.entries, node.entries.size() - 1, null);
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
    for (i in Nat.range(0, node.entries.size())) {
      let entry = node.entries[i];

      switch (entry.subtreeCID) {
        case (?cid) {
          switch (getNode(mst, cid)) {
            case (?subtree) {
              let isLast = i == (node.entries.size() - 1 : Nat);
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
    if (node.entries.size() == 0) {
      // Empty node is valid
      return #ok;
    };
    let firstEntry = node.entries[0];
    if (firstEntry.prefixLength != 0) {
      return #err("First entry in node must have prefixLength 0");
    };
    var key = firstEntry.keySuffix;
    let depth = calculateDepth(key);
    switch (parentDepth) {
      case (?pd) {
        if (depth >= pd) {
          return #err("Child depth must be less than parent depth");
        };
      };
      case null {};
    };
    let fullKeys = DynamicArray.DynamicArray<[Nat8]>(node.entries.size());
    fullKeys.add(key);
    var prevKey = key;
    for (i in Nat.range(1, node.entries.size())) {
      key := reconstructKey(node.entries, i, ?prevKey);
      fullKeys.add(key);

      let depth = calculateDepth(key);

      // Check depth consistency - all keys in node should have same depth
      let prevDepth = calculateDepth(prevKey);
      if (depth != prevDepth) {
        return #err("All entries in a node must have same depth");
      };
      prevKey := key;
    };

    // Validate entries are sorted
    for (i in Nat.range(1, node.entries.size())) {
      let prevKey = fullKeys.get(i - 1);
      let currKey = fullKeys.get(i);

      if (compareKeys(prevKey, currKey) != #less) {
        return #err("Entries must be sorted");
      };
    };

    // Get node depth for child validation
    let nodeDepth = if (node.entries.size() > 0) {
      ?calculateDepth(fullKeys.get(0));
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

  private func addOrUpdateInternal(
    mst : MerkleSearchTree,
    key : Text,
    value : CID.CID,
    addOnly : Bool,
  ) : Result.Result<MerkleSearchTree, Text> {
    let keyBytes = keyToBytes(key);
    if (keyBytes.size() == 0) return #err("Key cannot be empty");
    if (keyBytes.size() > 256) return #err("Key too long (max 256 bytes)");

    let node = getRootNode(mst);
    addRecursive(
      mst,
      node,
      mst.root,
      keyBytes,
      value,
      addOnly,
    );
  };

  private func addRecursive(
    mst : MerkleSearchTree,
    node : MerkleNode.Node,
    nodeCID : CID.CID,
    key : [Nat8],
    value : CID.CID,
    addOnly : Bool,
  ) : Result.Result<MerkleSearchTree, Text> {
    // Find position for new key
    var insertPos = 0;

    var prevKey : ?[Nat8] = null;
    label f for (i in Nat.range(0, node.entries.size())) {
      let entryKey = reconstructKey(node.entries, i, prevKey);

      switch (compareKeys(key, entryKey)) {
        case (#equal) {
          if (addOnly) return #err("Key already exists");
          // Update existing entry
          let entries = Array.tabulate<MerkleNode.TreeEntry>(
            node.entries.size(),
            func(j) = if (j == i) {
              { node.entries[j] with valueCID = value };
            } else {
              node.entries[j];
            },
          );
          let updatedNode = { node with entries };
          return #ok(replaceNode(mst, nodeCID, updatedNode));
        };
        case (#less) {
          insertPos := i;
          return insertAtPosition(mst, node, nodeCID, insertPos, key, value, addOnly);
        };
        case (#greater) insertPos := i + 1;
      };
      prevKey := ?entryKey;
    };

    // Insert at end or in appropriate position
    insertAtPosition(mst, node, nodeCID, insertPos, key, value, addOnly);
  };

  private func insertAtPosition(
    mst : MerkleSearchTree,
    node : MerkleNode.Node,
    nodeCID : CID.CID,
    pos : Nat,
    key : [Nat8],
    value : CID.CID,
    addOnly : Bool,
  ) : Result.Result<MerkleSearchTree, Text> {
    // Determine if key belongs at this level
    let nodeDepth = calculateDepth(reconstructKey(node.entries, 0, null));

    let keyDepth = calculateDepth(key);

    if (keyDepth == nodeDepth) {
      // Insert at this level
      let newEntries = insertAndCompress(node.entries, pos, key, value);
      let updatedNode = {
        node with
        entries = newEntries
      };

      #ok(replaceNode(mst, nodeCID, updatedNode));
    } else if (keyDepth < nodeDepth) {
      // Lower depth - goes in subtree
      let subtreeCID = if (pos == 0) node.leftSubtreeCID else {
        let lastPos : Nat = pos - 1;
        if (lastPos < node.entries.size()) {
          node.entries[lastPos].subtreeCID;
        } else {
          null;
        };
      };

      switch (subtreeCID) {
        case (?cid) {
          // Recursively add to subtree
          let ?subtree = getNode(mst, cid) else return #err("Subtree not found");
          switch (addRecursive(mst, subtree, cid, key, value, addOnly)) {
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

      let newEntries = insertAndCompress(node.entries, pos, key, value);

      let updatedNode = {
        node with
        entries = newEntries
      };

      #ok(replaceNode(mst, nodeCID, updatedNode));
    };
  };

  private func insertAndCompress(
    entries : [MerkleNode.TreeEntry],
    pos : Nat,
    key : [Nat8],
    value : CID.CID,
  ) : [MerkleNode.TreeEntry] {

    let prevFullKey = if (pos > 0) {
      ?reconstructKey(entries, pos - 1, null);
    } else null;

    let nextFullKey = if (pos < entries.size()) {
      ?reconstructKey(entries, pos, prevFullKey);
    } else null;

    let dynamicEntries = DynamicArray.fromArray<MerkleNode.TreeEntry>(entries);

    let newEntry : MerkleNode.TreeEntry = {
      prefixLength = 0;
      keySuffix = key;
      valueCID = value;
      subtreeCID = null;
    };
    dynamicEntries.insert(pos, newEntry);

    // Compress new entry relative to previous
    switch (prevFullKey) {
      case (?prevKey) {
        let prefixLen = findCommonPrefixLength(prevKey, key);
        let suffix = Array.sliceToArray(key, prefixLen, key.size());
        dynamicEntries.put(pos, { newEntry with prefixLength = prefixLen; keySuffix = suffix });
      };
      case (null) {};
    };

    // Recompress next entry relative to new key
    switch (nextFullKey) {
      case (?nextKey) {
        let nextEntry = dynamicEntries.get(pos + 1);
        let prefixLen = findCommonPrefixLength(key, nextKey);
        let suffix = Array.sliceToArray(nextKey, prefixLen, nextKey.size());
        dynamicEntries.put(pos + 1, { nextEntry with prefixLength = prefixLen; keySuffix = suffix });
      };
      case (null) {};
    };

    DynamicArray.toArray(dynamicEntries);
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
  ) : ?CID.CID {
    // Binary search through entries at this level
    var left = 0;
    var right = node.entries.size();

    while (left < right) {
      let mid = (left + right) / 2;
      let entryKey = reconstructKey(node.entries, mid, null); // TODO prevKeyCache?

      switch (compareKeys(keyBytes, entryKey)) {
        case (#equal) return ?node.entries[mid].valueCID;
        case (#less) right := mid;
        case (#greater) left := mid + 1;
      };
    };

    // Not found at this level, check appropriate subtree
    searchSubtree(mst, node, left, keyBytes);
  };

  private func searchSubtree(
    mst : MerkleSearchTree,
    node : MerkleNode.Node,
    index : Nat,
    key : [Nat8],
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
          case (?subtree) getRecursive(mst, subtree, key);
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
  ) : Result.Result<(MerkleSearchTree, CID.CID), Text> {

    let fullKeys = DynamicArray.DynamicArray<[Nat8]>(node.entries.size());
    // Find the key in current node
    var prevKeyOrNull : ?[Nat8] = null;
    label f for (i in Nat.range(0, node.entries.size())) {
      let entryKey = reconstructKey(node.entries, i, prevKeyOrNull);
      fullKeys.add(entryKey);

      if (compareKeys(entryKey, keyBytes) != #equal) {
        prevKeyOrNull := ?entryKey;
        continue f;
      };

      let entries = DynamicArray.fromArray<MerkleNode.TreeEntry>(node.entries);
      let removedEntry = entries.remove(i);
      switch (entries.getOpt(i)) {
        case (null) (); // Removed last entry, nothing to adjust
        case (?nextEntry) {
          // Adjust next entry's prefixLength and keySuffix
          let nextKey = reconstructKey(node.entries, i + 1, ?entryKey);
          let (newSuffix, newPrefixLength) = switch (prevKeyOrNull) {
            case (?prevKey) {
              // If there's a previous entry, adjust the next entry's suffix
              let prefixLength = findCommonPrefixLength(prevKey, nextKey);

              // Extract suffix after common prefix
              let suffix = Array.sliceToArray(nextKey, prefixLength, nextKey.size());
              (suffix, prefixLength);
            };
            case (null) {
              // If there's no previous entry, then should be the full key with no prefixLength
              let newSuffix = nextKey;
              (newSuffix, 0);
            };
          };
          entries.put(i, { nextEntry with keySuffix = newSuffix; prefixLength = newPrefixLength });
        };
      };

      let updatedNode = {
        node with
        entries = DynamicArray.toArray(entries)
      };

      let newMst = replaceNode(mst, nodeCID, updatedNode);

      return #ok((newMst, removedEntry.valueCID));
    };

    // Find appropriate subtree
    var searchPos = 0;
    label searchLoop for (i in Nat.range(0, node.entries.size())) {
      let entryKey = fullKeys.get(i);
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

        switch (removeRecursive(mst, subtree, cid, keyBytes)) {
          case (#ok((updatedMst, removedValue))) {
            let newSubtreeNode = getRootNode(updatedMst);

            // Check if subtree is now empty
            if (newSubtreeNode.entries.size() == 0 and newSubtreeNode.leftSubtreeCID == null) {
              // Remove empty subtree reference
              if (searchPos == 0) {
                let updatedNode = { node with leftSubtreeCID = null };
                let newMst = replaceNode(updatedMst, nodeCID, updatedNode);
                return #ok((newMst, removedValue));
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
                let newMst = replaceNode(updatedMst, nodeCID, updatedNode);
                return #ok((newMst, removedValue));
              };
            } else {
              // Update subtree reference
              if (searchPos == 0) {
                let updatedNode = {
                  node with leftSubtreeCID = ?updatedMst.root
                };
                let newMst = replaceNode(updatedMst, nodeCID, updatedNode);
                return #ok((newMst, removedValue));
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
                let newMst = replaceNode(updatedMst, nodeCID, updatedNode);
                return #ok((newMst, removedValue));
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
    var prevKey : ?[Nat8] = null;
    for (i in Nat.range(0, node.entries.size())) {
      let entry = node.entries[i];
      let key = reconstructKey(node.entries, i, prevKey);
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
      prevKey := ?key;
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
    prevKeyCache : ?[Nat8],
  ) : [Nat8] {
    if (index >= entries.size()) return [];

    if (index == 0) {
      return entries[0].keySuffix;
    };

    let entry = entries[index];
    let prevKey = switch (prevKeyCache) {
      case (?k) k;
      case (null) reconstructKey(entries, index - 1, null);
    };

    if (entry.prefixLength == 0) {
      return entry.keySuffix;
    };

    if (entry.prefixLength > prevKey.size()) {
      Runtime.trap("Invalid state: prefixLength exceeds previous key length. Expected at most " # Nat.toText(prevKey.size()) # " but got " # Nat.toText(entry.prefixLength));
    };

    let fullKey = DynamicArray.DynamicArray<Nat8>(entry.prefixLength + entry.keySuffix.size());
    for (b in prevKey.vals() |> Iter.take(_, entry.prefixLength)) {
      fullKey.add(b);
    };
    for (b in entry.keySuffix.vals()) {
      fullKey.add(b);
    };

    DynamicArray.toArray(fullKey);
  };

  private func findCommonPrefixLength(a : [Nat8], b : [Nat8]) : Nat {
    let minLen = Nat.min(a.size(), b.size());
    var i = 0;

    while (i < minLen and a[i] == b[i]) {
      i += 1;
    };

    i;
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
