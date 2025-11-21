import Result "mo:core@1/Result";
import CID "mo:cid@1";
import Blob "mo:core@1/Blob";
import DynamicArray "mo:xtended-collections@0/DynamicArray";
import Text "mo:core@1/Text";
import Sha256 "mo:sha2@0/Sha256";
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
    nodes : PureMap.Map<CID.CID, MerkleNode.Node>; // All nodes, including historical/orphaned ones
  };

  public type TreeDiff = {
    nodes : [(CID.CID, MerkleNode.Node)];
    recordIds : [CID.CID];
  };

  public type SizeOptions = {
    includeHistorical : Bool;
  };

  public type EntriesOptions = {
    includeHistorical : Bool;
  };

  public type KeysOptions = {
    includeHistorical : Bool;
  };

  public type ValuesOptions = {
    includeHistorical : Bool;
  };

  public type NodesOptions = {
    includeHistorical : Bool;
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
    sizeAdvanced(mst, { includeHistorical = false });
  };

  public func sizeAdvanced(mst : MerkleSearchTree, options : SizeOptions) : Nat {
    var count = 0;
    traverseTree(
      mst,
      options.includeHistorical,
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
    switch (removeRecursive(mst, node, keyBytes)) {
      case (#ok({ updatedNodeData = { newNodes; newNodeCID }; removedEntryValue })) {
        #ok(({ root = newNodeCID; nodes = newNodes }, removedEntryValue));
      };
      case (#err(e)) #err(e);
    };
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
    entriesAdvanced(mst, { includeHistorical = false });
  };

  public func entriesAdvanced(mst : MerkleSearchTree, options : EntriesOptions) : Iter.Iter<(Text, CID.CID)> {
    // TODO optimize by not creating list?
    let records = List.empty<(Text, CID.CID)>();

    traverseTree(
      mst,
      options.includeHistorical,
      func(key : Text, value : CID.CID) {
        List.add(records, (key, value));
      },
    );
    List.values(records);
  };

  public func nodes(mst : MerkleSearchTree) : Iter.Iter<(CID.CID, MerkleNode.Node)> {
    nodesAdvanced(mst, { includeHistorical = false });
  };

  public func nodesAdvanced(mst : MerkleSearchTree, options : NodesOptions) : Iter.Iter<(CID.CID, MerkleNode.Node)> {
    if (options.includeHistorical) {
      // Return all nodes
      return PureMap.entries(mst.nodes);
    };
    let rootNode = getRootNode(mst);
    let nodeList = List.empty<(CID.CID, MerkleNode.Node)>();
    iterateNodes(
      mst,
      rootNode,
      mst.root,
      func(nodeId : CID.CID, node : MerkleNode.Node) {
        List.add(nodeList, (nodeId, node));
      },
    );
    List.values(nodeList);
  };

  public func changesSince(
    mst : MerkleSearchTree,
    previousRoot : CID.CID,
  ) : TreeDiff {
    let prevMst = {
      root = previousRoot;
      nodes = mst.nodes;
    };
    let prevRootNode = getRootNode(prevMst);
    let prevNodeIds = List.empty<CID.CID>();
    let prevRecordIds = List.empty<CID.CID>();
    iterateNodes(
      prevMst,
      prevRootNode,
      prevMst.root,
      func(nodeId : CID.CID, node : MerkleNode.Node) {
        List.add(prevNodeIds, nodeId);
        for (entry in node.entries.vals()) {
          List.add(prevRecordIds, entry.valueCID);
        };
      },
    );
    let prevNodeIdSet = Set.fromIter(List.values(prevNodeIds), CIDBuilder.compare);
    let prevRecordIdSet = Set.fromIter(List.values(prevRecordIds), CIDBuilder.compare);

    let rootNode = getRootNode(mst);
    let nodes = List.empty<(CID.CID, MerkleNode.Node)>();
    let recordIds = List.empty<CID.CID>();
    iterateNodes(
      mst,
      rootNode,
      mst.root,
      func(nodeId : CID.CID, node : MerkleNode.Node) {
        if (not Set.contains(prevNodeIdSet, CIDBuilder.compare, nodeId)) {
          List.add(nodes, (nodeId, node));
        };
        for (entry in node.entries.vals()) {
          if (not Set.contains(prevRecordIdSet, CIDBuilder.compare, entry.valueCID)) {
            List.add(recordIds, entry.valueCID);
          };
        };
      },
    );
    {
      nodes = List.toArray(nodes);
      recordIds = List.toArray(recordIds);
    };
  };

  private func iterateNodes(
    mst : MerkleSearchTree,
    node : MerkleNode.Node,
    nodeCID : CID.CID,
    callback : (nodeId : CID.CID, node : MerkleNode.Node) -> (),
  ) {
    callback(nodeCID, node);
    // Process left subtree
    switch (node.leftSubtreeCID) {
      case (?cid) {
        switch (getNode(mst, cid)) {
          case (?subtree) iterateNodes(mst, subtree, cid, callback);
          case (null) ();
        };
      };
      case (null) ();
    };

    for (entry in node.entries.vals()) {
      switch (entry.subtreeCID) {
        case (?cid) {
          switch (getNode(mst, cid)) {
            case (?subtree) iterateNodes(mst, subtree, cid, callback);
            case (null) ();
          };
        };
        case (null) ();
      };
    };
  };

  public func keys(mst : MerkleSearchTree) : Iter.Iter<Text> {
    keysAdvanced(mst, { includeHistorical = false });
  };

  public func keysAdvanced(mst : MerkleSearchTree, options : KeysOptions) : Iter.Iter<Text> {
    // TODO optimize by not creating list?
    let keys = List.empty<Text>();

    traverseTree(
      mst,
      options.includeHistorical,
      func(key : Text, value : CID.CID) {
        List.add(keys, key);
      },
    );

    List.values(keys);
  };

  public func values(mst : MerkleSearchTree) : Iter.Iter<CID.CID> {
    valuesAdvanced(mst, { includeHistorical = false });
  };

  public func valuesAdvanced(mst : MerkleSearchTree, options : ValuesOptions) : Iter.Iter<CID.CID> {
    // TODO optimize by not creating list?
    let values = List.empty<CID.CID>();

    traverseTree(
      mst,
      options.includeHistorical,
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
    let rootNode = getRootNode(mst);
    let keyMap = PureMap.empty<Text, Text>();
    let shortKeyCounts = PureMap.empty<Text, Nat>();

    let allKeys = List.empty<Text>();
    collectKeys(mst, rootNode, allKeys);

    let allNodeCIDs = List.empty<CID.CID>();
    collectNodeCIDs(mst, rootNode, mst.root, allNodeCIDs);

    var legend = keyMap;
    var counts = shortKeyCounts;
    let legendEntries = List.empty<(Text, Text)>();

    for (fullKey in List.values(allKeys)) {
      let baseShort = shortenKey(fullKey);
      let count = switch (PureMap.get(counts, Text.compare, baseShort)) {
        case (?n) n;
        case null 0;
      };
      counts := PureMap.add(counts, Text.compare, baseShort, count + 1);

      let shortKey = if (count == 0) baseShort else baseShort # "(" # Nat.toText(count + 1) # ")";
      legend := PureMap.add(legend, Text.compare, fullKey, shortKey);
      List.add(legendEntries, (shortKey, fullKey));
    };

    var nodeLegend = PureMap.empty<Text, Text>();
    var nodeCounts = PureMap.empty<Text, Nat>();
    let nodeLegendEntries = List.empty<(Text, Text)>();

    for (cid in List.values(allNodeCIDs)) {
      let fullCID = CID.toText(cid);
      let baseShort = "N-" # shortenKey(fullCID);
      let count = switch (PureMap.get(nodeCounts, Text.compare, baseShort)) {
        case (?n) n;
        case null 0;
      };
      nodeCounts := PureMap.add(nodeCounts, Text.compare, baseShort, count + 1);

      let shortName = if (count == 0) baseShort else baseShort # "(" # Nat.toText(count + 1) # ")";
      nodeLegend := PureMap.add(nodeLegend, Text.compare, fullCID, shortName);
      List.add(nodeLegendEntries, (shortName, fullCID));
    };

    let treeResult = renderNodeTree(mst, rootNode, mst.root, legend, nodeLegend);

    let allLines = List.empty<Text>();
    List.add(allLines, "Legend:");
    List.add(allLines, "  Keys:");
    for ((short, full) in List.values(legendEntries)) {
      List.add(allLines, "    " # short # ": " # full);
    };
    List.add(allLines, "  Nodes:");
    for ((short, full) in List.values(nodeLegendEntries)) {
      List.add(allLines, "    " # short # ": " # full);
    };
    List.add(allLines, "");
    for (l in treeResult.lines.vals()) {
      List.add(allLines, "~" # trimRight(l));
    };

    Text.join("\n", List.values(allLines));
  };

  private func collectKeys(mst : MerkleSearchTree, node : MerkleNode.Node, keys : List.List<Text>) {
    switch (node.leftSubtreeCID) {
      case (?cid) {
        switch (getNode(mst, cid)) {
          case (?sub) collectKeys(mst, sub, keys);
          case null {};
        };
      };
      case null {};
    };

    var prevKey : ?[Nat8] = null;
    for (i in Nat.range(0, node.entries.size())) {
      let entry = node.entries[i];
      let key = reconstructKey(node.entries, i, prevKey);
      List.add(keys, keyToText(key));

      switch (entry.subtreeCID) {
        case (?cid) {
          switch (getNode(mst, cid)) {
            case (?sub) collectKeys(mst, sub, keys);
            case null {};
          };
        };
        case null {};
      };
      prevKey := ?key;
    };
  };

  private func collectNodeCIDs(mst : MerkleSearchTree, node : MerkleNode.Node, nodeCID : CID.CID, cids : List.List<CID.CID>) {
    List.add(cids, nodeCID);

    switch (node.leftSubtreeCID) {
      case (?cid) {
        switch (getNode(mst, cid)) {
          case (?sub) collectNodeCIDs(mst, sub, cid, cids);
          case null {};
        };
      };
      case null {};
    };

    for (entry in node.entries.vals()) {
      switch (entry.subtreeCID) {
        case (?cid) {
          switch (getNode(mst, cid)) {
            case (?sub) collectNodeCIDs(mst, sub, cid, cids);
            case null {};
          };
        };
        case null {};
      };
    };
  };

  private func shortenKey(key : Text) : Text {
    let chars = Text.toArray(key);
    if (chars.size() <= 3) return key;
    Text.fromIter(Array.sliceToArray(chars, (chars.size() - 3 : Nat), chars.size()).vals());
  };

  private func renderNodeTree(
    mst : MerkleSearchTree,
    node : MerkleNode.Node,
    nodeCID : CID.CID,
    legend : PureMap.Map<Text, Text>,
    nodeLegend : PureMap.Map<Text, Text>,
  ) : { lines : [Text]; width : Nat; rootPos : Nat } {
    let nodeLabel = switch (PureMap.get(nodeLegend, Text.compare, CID.toText(nodeCID))) {
      case (?s) s;
      case null "N-???";
    };

    type Entry = {
      label_ : Text;
      subtree : ?{ node : MerkleNode.Node; cid : CID.CID };
    };
    let children = List.empty<Entry>();

    switch (node.leftSubtreeCID) {
      case (?cid) {
        switch (getNode(mst, cid)) {
          case (?sub) {
            let subLabel = switch (PureMap.get(nodeLegend, Text.compare, CID.toText(cid))) {
              case (?s) s;
              case null "N-???";
            };
            List.add(children, { label_ = subLabel; subtree = ?{ node = sub; cid = cid } });
          };
          case null {};
        };
      };
      case null {};
    };

    var prevKey : ?[Nat8] = null;
    for (i in Nat.range(0, node.entries.size())) {
      let entry = node.entries[i];
      let key = reconstructKey(node.entries, i, prevKey);
      let fullKeyText = keyToText(key);
      let shortKey = switch (PureMap.get(legend, Text.compare, fullKeyText)) {
        case (?s) s;
        case null fullKeyText;
      };
      List.add(children, { label_ = shortKey; subtree = null });

      switch (entry.subtreeCID) {
        case (?cid) {
          switch (getNode(mst, cid)) {
            case (?sub) {
              let subLabel = switch (PureMap.get(nodeLegend, Text.compare, CID.toText(cid))) {
                case (?s) s;
                case null "N-???";
              };
              List.add(children, { label_ = subLabel; subtree = ?{ node = sub; cid = cid } });
            };
            case null {};
          };
        };
        case null {};
      };
      prevKey := ?key;
    };

    let childArray = List.toArray(children);
    if (childArray.size() == 0) {
      return {
        lines = [nodeLabel];
        width = nodeLabel.size();
        rootPos = nodeLabel.size() / 2;
      };
    };

    type Rendered = { lines : [Text]; width : Nat; rootPos : Nat };
    let rendered = Array.map<Entry, Rendered>(
      childArray,
      func(c) {
        switch (c.subtree) {
          case (?sub) {
            let result = renderNodeTree(mst, sub.node, sub.cid, legend, nodeLegend);
            let width = Nat.max(result.width, c.label_.size());
            { lines = result.lines; width; rootPos = result.rootPos };
          };
          case null {
            let width = c.label_.size();
            { lines = [c.label_]; width; rootPos = width / 2 };
          };
        };
      },
    );

    let gap = 3;
    let totalWidth = Array.foldLeft<Rendered, Nat>(rendered, 0, func(acc, r) = acc + r.width) + gap * (rendered.size() - 1 : Nat);
    let maxHeight = Array.foldLeft<Rendered, Nat>(rendered, 0, func(acc, r) = Nat.max(acc, r.lines.size()));

    let combined = DynamicArray.DynamicArray<Text>(maxHeight);
    for (row in Nat.range(0, maxHeight)) {
      var line = "";
      for (i in Nat.range(0, rendered.size())) {
        let r = rendered[i];
        let text = if (row < r.lines.size()) r.lines[row] else "";
        line #= padCenter(text, r.width);
        if (i + 1 < rendered.size()) line #= repeatChar(' ', gap);
      };
      combined.add(line);
    };

    let positions = DynamicArray.DynamicArray<Nat>(rendered.size());
    var pos = 0;
    for (i in Nat.range(0, rendered.size())) {
      positions.add(pos + rendered[i].rootPos);
      pos += rendered[i].width + gap;
    };

    let connectorLine = buildConnector(DynamicArray.toArray(positions), totalWidth);
    let childrenCenter = (positions.get(0) + positions.get(rendered.size() - 1)) / 2;
    let labelStart = if (nodeLabel.size() / 2 > childrenCenter) 0 else (childrenCenter - nodeLabel.size() / 2 : Nat);
    let padRight = if (labelStart + nodeLabel.size() >= totalWidth) 0 else (totalWidth - labelStart - nodeLabel.size() : Nat);
    let rootLine = repeatChar(' ', labelStart) # nodeLabel # repeatChar(' ', padRight);
    let stemLine = repeatChar(' ', childrenCenter) # "|" # repeatChar(' ', if (childrenCenter + 1 >= totalWidth) 0 else (totalWidth - childrenCenter - 1 : Nat));

    {
      lines = Array.concat([rootLine, stemLine, connectorLine], DynamicArray.toArray(combined));
      width = totalWidth;
      rootPos = childrenCenter;
    };
  };
  private func trimRight(s : Text) : Text {
    let chars = Text.toArray(s);
    var endIndex = chars.size();
    while (endIndex > 0 and chars[endIndex - 1] == ' ') {
      endIndex -= 1;
    };
    if (endIndex == 0) return "";
    Text.fromIter(Array.sliceToArray(chars, 0, endIndex).vals());
  };

  private func buildConnector(positions : [Nat], totalWidth : Nat) : Text {
    if (positions.size() == 0) return "";
    let leftmost = positions[0];
    let rightmost = positions[positions.size() - 1];

    let chars = Array.tabulate<Char>(
      totalWidth,
      func(i) {
        if (i < leftmost or i > rightmost) ' ' else if (Array.indexOf<Nat>(positions, Nat.equal, i) != null) '|' else '_';
      },
    );
    Text.fromIter(chars.vals());
  };

  private func repeatChar(c : Char, n : Nat) : Text {
    Text.fromIter(Iter.map<Nat, Char>(Nat.range(0, n), func(_) = c));
  };

  private func padCenter(s : Text, width : Nat) : Text {
    let len = s.size();
    if (len >= width) return s;
    let left : Nat = (width - len) / 2;
    let right : Nat = width - len - left;
    repeatChar(' ', left) # s # repeatChar(' ', right);
  };

  private func traverseTree(
    mst : MerkleSearchTree,
    includeHistorical : Bool,
    onEntry : (key : Text, value : CID.CID) -> (),
  ) {
    if (includeHistorical) {
      let uniqueKeys = Set.empty<Text>();
      // Use all nodes, not just reachable ones
      for ((_, node) in PureMap.entries(mst.nodes)) {
        var prevKey : ?[Nat8] = null;
        for (i in Nat.range(0, node.entries.size())) {
          let entry = node.entries[i];
          let key = reconstructKey(node.entries, i, prevKey);
          let keyText = keyToText(key);
          let uniqueKey = keyText # "~" # CID.toText(entry.valueCID);
          if (not Set.contains(uniqueKeys, Text.compare, uniqueKey)) {
            Set.add(uniqueKeys, Text.compare, uniqueKey);
            // Historical keys may be in multiple nodes, so deduplicate
            onEntry(keyText, entry.valueCID);
          };
          prevKey := ?key;
        };
      };
    } else {
      let rootNode = getRootNode(mst);
      traverseTreeNode(
        mst,
        rootNode,
        func(key : [Nat8], value : CID.CID) {
          onEntry(keyToText(key), value);
        },
      );
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

  // PRIVATE HELPER FUNCTIONS

  private func loadNodeRecursive(
    cid : CID.CID,
    blockMap : PureMap.Map<CID.CID, Blob>,
    nodes : PureMap.Map<CID.CID, MerkleNode.Node>,
  ) : Result.Result<PureMap.Map<CID.CID, MerkleNode.Node>, Text> {

    // Check if already loaded
    switch (PureMap.get(nodes, CIDBuilder.compare, cid)) {
      case (?_) return #ok(nodes);
      case (null) {};
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
    switch (addRecursive(mst, node, keyBytes, value, addOnly)) {
      case (#ok({ newNodes; newNodeCID })) #ok({
        root = newNodeCID;
        nodes = newNodes;
      });
      case (#err(e)) #err(e);
    };
  };

  type UpdatedNodeData = {
    newNodes : PureMap.Map<CID.CID, MerkleNode.Node>;
    newNodeCID : CID.CID;
  };

  private func addRecursive(
    mst : MerkleSearchTree,
    node : MerkleNode.Node,
    key : [Nat8],
    value : CID.CID,
    addOnly : Bool,
  ) : Result.Result<UpdatedNodeData, Text> {
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
          return #ok(addNode(mst.nodes, updatedNode));
        };
        case (#less) {
          insertPos := i;
          return insertAtPosition(mst, node, insertPos, key, value, addOnly);
        };
        case (#greater) insertPos := i + 1;
      };
      prevKey := ?entryKey;
    };

    // Insert at end or in appropriate position
    insertAtPosition(mst, node, insertPos, key, value, addOnly);
  };

  private func insertAtPosition(
    mst : MerkleSearchTree,
    node : MerkleNode.Node,
    pos : Nat,
    key : [Nat8],
    value : CID.CID,
    addOnly : Bool,
  ) : Result.Result<UpdatedNodeData, Text> {
    // Empty node - just add the entry directly
    if (node.entries.size() == 0) {
      let newEntries = [{
        prefixLength = 0;
        keySuffix = key;
        valueCID = value;
        subtreeCID = null;
      }];
      let updatedNode = { node with entries = newEntries };
      return #ok(addNode(mst.nodes, updatedNode));
    };

    // Determine if key belongs at this level
    let nodeDepth = calculateDepth(reconstructKey(node.entries, 0, null));
    let keyDepth = calculateDepth(key);

    if (keyDepth == nodeDepth) {
      // Insert at this level
      let newEntries = insertAndCompress(node.entries, pos, key, value);
      let updatedNode = { node with entries = newEntries };
      #ok(addNode(mst.nodes, updatedNode));
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
          switch (addRecursive(mst, subtree, key, value, addOnly)) {
            case (#ok({ newNodes; newNodeCID = newSubtreeCID })) {
              #ok(updateNodeSubtreeAndAdd(newNodes, node, pos, ?newSubtreeCID));
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
          let { newNodes; newNodeCID = newSubtreeCID } = addNode(mst.nodes, newSubtree);
          #ok(updateNodeSubtreeAndAdd(newNodes, node, pos, ?newSubtreeCID));
        };
      };
    } else {
      // keyDepth > nodeDepth
      // Higher depth key creates a new layer on top
      // Three cases based on where the key falls relative to existing entries

      if (pos == 0) {
        // Case 1: Before everything
        // Key comes before all current entries, but at higher level
        // Need to partition node.leftSubtreeCID around the new key

        var currentNodes = mst.nodes;
        var leftPartitionCID : ?CID.CID = null;
        var rightPartitionCID : ?CID.CID = null;

        switch (node.leftSubtreeCID) {
          case (?leftCID) {
            let ?leftSubtree = getNode(mst, leftCID) else return #err("Left subtree not found");
            switch (partitionSubtree({ root = leftCID; nodes = currentNodes }, leftSubtree, key)) {
              case (#ok({ leftCID = lCID; rightCID = rCID; nodes })) {
                leftPartitionCID := lCID;
                rightPartitionCID := rCID;
                currentNodes := nodes;
              };
              case (#err(e)) return #err(e);
            };
          };
          case (null) {};
        };

        // Right node contains all original entries with updated leftSubtreeCID
        let rightNode : MerkleNode.Node = {
          leftSubtreeCID = rightPartitionCID;
          entries = node.entries;
        };
        let { newNodes = nodesAfterRight; newNodeCID = rightNodeCID } = addNode(currentNodes, rightNode);

        // New root with the new key
        let newRootNode : MerkleNode.Node = {
          leftSubtreeCID = leftPartitionCID;
          entries = [{
            prefixLength = 0;
            keySuffix = key;
            valueCID = value;
            subtreeCID = ?rightNodeCID;
          }];
        };
        #ok(addNode(nodesAfterRight, newRootNode));

      } else if (pos >= node.entries.size()) {
        // Case 3: After everything
        // Key comes after all current entries, but at higher level
        // Need to partition the last entry's subtree

        var currentNodes = mst.nodes;
        var leftPartitionCID : ?CID.CID = null;
        var rightPartitionCID : ?CID.CID = null;

        let lastIdx : Nat = node.entries.size() - 1;
        switch (node.entries[lastIdx].subtreeCID) {
          case (?subtreeCID) {
            let ?subtree = getNode(mst, subtreeCID) else return #err("Subtree not found");
            switch (partitionSubtree({ root = subtreeCID; nodes = currentNodes }, subtree, key)) {
              case (#ok({ leftCID = lCID; rightCID = rCID; nodes })) {
                leftPartitionCID := lCID;
                rightPartitionCID := rCID;
                currentNodes := nodes;
              };
              case (#err(e)) return #err(e);
            };
          };
          case (null) {};
        };

        // Update last entry's subtree to point to left partition
        let updatedEntries = Array.tabulate<MerkleNode.TreeEntry>(
          node.entries.size(),
          func(i) = if (i == lastIdx) {
            { node.entries[i] with subtreeCID = leftPartitionCID };
          } else {
            node.entries[i];
          },
        );

        let leftNode : MerkleNode.Node = {
          leftSubtreeCID = node.leftSubtreeCID;
          entries = updatedEntries;
        };
        let { newNodes = nodesAfterLeft; newNodeCID = leftNodeCID } = addNode(currentNodes, leftNode);

        // New root
        let newRootNode : MerkleNode.Node = {
          leftSubtreeCID = ?leftNodeCID;
          entries = [{
            prefixLength = 0;
            keySuffix = key;
            valueCID = value;
            subtreeCID = rightPartitionCID;
          }];
        };
        #ok(addNode(nodesAfterLeft, newRootNode));

      } else {
        // Case 2: Splits in the middle
        // Key falls between entries[pos-1] and entries[pos], but at higher level
        // Must partition the middle subtree and split the node

        var currentNodes = mst.nodes;
        var leftPartitionCID : ?CID.CID = null;
        var rightPartitionCID : ?CID.CID = null;

        // Partition the middle subtree (between entries[pos-1] and entries[pos])
        switch (node.entries[pos - 1].subtreeCID) {
          case (?subtreeCID) {
            let ?subtree = getNode(mst, subtreeCID) else return #err("Middle subtree not found");
            switch (partitionSubtree({ root = subtreeCID; nodes = currentNodes }, subtree, key)) {
              case (#ok({ leftCID = lCID; rightCID = rCID; nodes })) {
                leftPartitionCID := lCID;
                rightPartitionCID := rCID;
                currentNodes := nodes;
              };
              case (#err(e)) return #err(e);
            };
          };
          case (null) {};
        };

        // Build left node: entries[0..pos-1] with last entry pointing to left partition
        let leftEntries = Array.tabulate<MerkleNode.TreeEntry>(
          pos,
          func(i) = if (i == (pos - 1 : Nat)) {
            { node.entries[i] with subtreeCID = leftPartitionCID };
          } else {
            node.entries[i];
          },
        );
        let leftNode : MerkleNode.Node = {
          leftSubtreeCID = node.leftSubtreeCID;
          entries = leftEntries;
        };
        let { newNodes = nodesAfterLeft; newNodeCID = leftNodeCID } = addNode(currentNodes, leftNode);

        // Build right node: right partition as left subtree, entries[pos..] recompressed
        let rightEntries = recompressEntries(node.entries, pos);
        let rightNode : MerkleNode.Node = {
          leftSubtreeCID = rightPartitionCID;
          entries = rightEntries;
        };
        let { newNodes = nodesAfterRight; newNodeCID = rightNodeCID } = addNode(nodesAfterLeft, rightNode);

        // Build new root with new key bridging left and right
        let newRootNode : MerkleNode.Node = {
          leftSubtreeCID = ?leftNodeCID;
          entries = [{
            prefixLength = 0;
            keySuffix = key;
            valueCID = value;
            subtreeCID = ?rightNodeCID;
          }];
        };
        #ok(addNode(nodesAfterRight, newRootNode));
      };
    };
  };

  // Partitions a subtree around a split key
  // Returns left partition (keys < splitKey) and right partition (keys > splitKey)
  private func partitionSubtree(
    mst : MerkleSearchTree,
    subtreeRoot : MerkleNode.Node,
    splitKey : [Nat8],
  ) : Result.Result<{ leftCID : ?CID.CID; rightCID : ?CID.CID; nodes : PureMap.Map<CID.CID, MerkleNode.Node> }, Text> {
    // Collect all entries from subtree, partitioned by splitKey
    let leftEntries = List.empty<(Text, CID.CID)>();
    let rightEntries = List.empty<(Text, CID.CID)>();

    traverseTreeNode(
      mst,
      subtreeRoot,
      func(entryKey : [Nat8], valueCID : CID.CID) {
        let keyText = keyToText(entryKey);
        if (compareKeys(entryKey, splitKey) == #less) {
          List.add(leftEntries, (keyText, valueCID));
        } else {
          List.add(rightEntries, (keyText, valueCID));
        };
      },
    );

    var currentNodes = mst.nodes;

    // Build left subtree if non-empty
    let leftCID : ?CID.CID = if (List.size(leftEntries) == 0) {
      null;
    } else {
      var tempMst = empty();
      for ((keyText, valueCID) in List.values(leftEntries)) {
        switch (put(tempMst, keyText, valueCID)) {
          case (#ok(newMst)) { tempMst := newMst };
          case (#err(e)) return #err("Failed to build left partition: " # e);
        };
      };
      // Merge nodes from temp tree
      for ((cid, node) in PureMap.entries(tempMst.nodes)) {
        currentNodes := PureMap.add(currentNodes, CIDBuilder.compare, cid, node);
      };
      ?tempMst.root;
    };

    // Build right subtree if non-empty
    let rightCID : ?CID.CID = if (List.size(rightEntries) == 0) {
      null;
    } else {
      var tempMst = empty();
      for ((keyText, valueCID) in List.values(rightEntries)) {
        switch (put(tempMst, keyText, valueCID)) {
          case (#ok(newMst)) { tempMst := newMst };
          case (#err(e)) return #err("Failed to build right partition: " # e);
        };
      };
      // Merge nodes from temp tree
      for ((cid, node) in PureMap.entries(tempMst.nodes)) {
        currentNodes := PureMap.add(currentNodes, CIDBuilder.compare, cid, node);
      };
      ?tempMst.root;
    };

    #ok({ leftCID; rightCID; nodes = currentNodes });
  };

  // Recompresses entries starting from startIndex with fresh prefix lengths
  private func recompressEntries(
    originalEntries : [MerkleNode.TreeEntry],
    startIndex : Nat,
  ) : [MerkleNode.TreeEntry] {
    let count : Nat = originalEntries.size() - startIndex;
    if (count == 0) return [];

    // Reconstruct full keys first
    let fullKeys = Array.tabulate<[Nat8]>(
      count,
      func(i) = reconstructKey(originalEntries, startIndex + i, null),
    );

    // Recompress relative to each other
    Array.tabulate<MerkleNode.TreeEntry>(
      count,
      func(i) {
        let entry = originalEntries[startIndex + i];
        let fullKey = fullKeys[i];

        if (i == 0) {
          // First entry has no prefix compression
          { entry with prefixLength = 0; keySuffix = fullKey };
        } else {
          let prevKey = fullKeys[i - 1];
          let prefixLen = findCommonPrefixLength(prevKey, fullKey);
          let suffix = Array.sliceToArray(fullKey, prefixLen, fullKey.size());
          { entry with prefixLength = prefixLen; keySuffix = suffix };
        };
      },
    );
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

  private func addNode(
    nodes : PureMap.Map<CID.CID, MerkleNode.Node>,
    newNode : MerkleNode.Node,
  ) : UpdatedNodeData {
    let newCID = CIDBuilder.fromMSTNode(newNode);
    let newNodes = PureMap.add(nodes, CIDBuilder.compare, newCID, newNode);
    // Don't remove old node to keep history
    {
      newNodes = newNodes;
      newNodeCID = newCID;
    };
  };

  // Helper that updates a node's subtree at the given position and adds it to the node map
  private func updateNodeSubtreeAndAdd(
    nodes : PureMap.Map<CID.CID, MerkleNode.Node>,
    node : MerkleNode.Node,
    position : Nat,
    newSubtreeCID : ?CID.CID,
  ) : UpdatedNodeData {
    let updatedNode = if (position == 0) {
      { node with leftSubtreeCID = newSubtreeCID };
    } else {
      let entries = Array.tabulate<MerkleNode.TreeEntry>(
        node.entries.size(),
        func(i) = if (i == (position - 1 : Nat)) {
          { node.entries[i] with subtreeCID = newSubtreeCID };
        } else {
          node.entries[i];
        },
      );
      { node with entries };
    };
    addNode(nodes, updatedNode);
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
    keyBytes : [Nat8],
  ) : Result.Result<{ updatedNodeData : UpdatedNodeData; removedEntryValue : CID.CID }, Text> {

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

      // Found the entry to remove
      let removedEntry = node.entries[i];
      let entries = DynamicArray.fromArray<MerkleNode.TreeEntry>(node.entries);
      let _ = entries.remove(i);

      // Handle the right subtree of the removed entry
      // The right subtree needs to be merged into the remaining structure
      switch (removedEntry.subtreeCID) {
        case (?rightSubtreeCID) {
          // The removed entry had a right subtree
          // This subtree needs to be preserved

          if (i < entries.size()) {
            // There's a next entry after the removed one
            // Merge the right subtree with the next entry
            let nextEntry = entries.get(i);
            let nextKey = reconstructKey(node.entries, i + 1, ?entryKey);

            // Recompute the next entry's prefix relative to the previous entry
            let (newSuffix, newPrefixLength) = switch (prevKeyOrNull) {
              case (?prevKey) {
                let prefixLength = findCommonPrefixLength(prevKey, nextKey);
                let suffix = Array.sliceToArray(nextKey, prefixLength, nextKey.size());
                (suffix, prefixLength);
              };
              case (null) {
                (nextKey, 0);
              };
            };

            // We need to merge rightSubtreeCID entries with the current structure
            // The rightSubtreeCID should be re-inserted into the tree
            // For now, we need to handle this by merging all entries from the subtree
            let ?rightSubtreeNode = getNode(mst, rightSubtreeCID) else return #err("Right subtree not found");

            // Collect all entries from the right subtree
            let subtreeEntries = List.empty<(Text, CID.CID)>();
            traverseTreeNode(
              mst,
              rightSubtreeNode,
              func(key : [Nat8], value : CID.CID) {
                List.add(subtreeEntries, (keyToText(key), value));
              },
            );

            // Update the current entry
            entries.put(
              i,
              {
                prefixLength = newPrefixLength;
                keySuffix = newSuffix;
                valueCID = nextEntry.valueCID;
                subtreeCID = nextEntry.subtreeCID;
              },
            );

            // Create the updated node
            let updatedNode = {
              node with
              entries = DynamicArray.toArray(entries)
            };
            let newNodes = addNode(mst.nodes, updatedNode);

            // Re-insert all entries from the right subtree
            var currentNodes = newNodes.newNodes;
            var currentNodeCID = newNodes.newNodeCID;

            for ((keyText, valueCID) in List.values(subtreeEntries)) {
              let keyBytes = keyToBytes(keyText);
              let ?currentNode = getNode({ root = currentNodeCID; nodes = currentNodes }, currentNodeCID) else return #err("Current node not found");

              switch (addRecursive({ root = currentNodeCID; nodes = currentNodes }, currentNode, keyBytes, valueCID, false)) {
                case (#ok({ newNodes = updatedNodes; newNodeCID = updatedCID })) {
                  currentNodes := updatedNodes;
                  currentNodeCID := updatedCID;
                };
                case (#err(e)) return #err("Failed to re-insert entry: " # e);
              };
            };

            return #ok({
              updatedNodeData = {
                newNodes = currentNodes;
                newNodeCID = currentNodeCID;
              };
              removedEntryValue = removedEntry.valueCID;
            });
          } else {
            // This was the last entry
            // Attach the right subtree to the previous entry
            if (i > 0) {
              let prevEntry = entries.get(i - 1);
              entries.put(i - 1, { prevEntry with subtreeCID = ?rightSubtreeCID });
            } else {
              // This was the only entry and it had a right subtree
              // Need to merge the leftSubtree with the right subtree
              switch (node.leftSubtreeCID) {
                case (?leftSubtreeCID) {
                  // Both subtrees exist, need to merge them
                  let ?rightSubtreeNode = getNode(mst, rightSubtreeCID) else return #err("Right subtree not found");

                  // Collect all entries from right subtree
                  let subtreeEntries = List.empty<(Text, CID.CID)>();
                  traverseTreeNode(
                    mst,
                    rightSubtreeNode,
                    func(key : [Nat8], value : CID.CID) {
                      List.add(subtreeEntries, (keyToText(key), value));
                    },
                  );

                  // Start with left subtree as the new root
                  var currentNodes = mst.nodes;
                  var currentNodeCID = leftSubtreeCID;

                  // Re-insert all entries from the right subtree
                  for ((keyText, valueCID) in List.values(subtreeEntries)) {
                    let keyBytes = keyToBytes(keyText);
                    let ?currentNode = getNode({ root = currentNodeCID; nodes = currentNodes }, currentNodeCID) else return #err("Current node not found");

                    switch (addRecursive({ root = currentNodeCID; nodes = currentNodes }, currentNode, keyBytes, valueCID, false)) {
                      case (#ok({ newNodes = updatedNodes; newNodeCID = updatedCID })) {
                        currentNodes := updatedNodes;
                        currentNodeCID := updatedCID;
                      };
                      case (#err(e)) return #err("Failed to re-insert entry: " # e);
                    };
                  };

                  return #ok({
                    updatedNodeData = {
                      newNodes = currentNodes;
                      newNodeCID = currentNodeCID;
                    };
                    removedEntryValue = removedEntry.valueCID;
                  });
                };
                case (null) {
                  // Only right subtree exists, return it as the new root
                  return #ok({
                    updatedNodeData = {
                      newNodes = mst.nodes;
                      newNodeCID = rightSubtreeCID;
                    };
                    removedEntryValue = removedEntry.valueCID;
                  });
                };
              };
            };
          };
        };
        case (null) {
          // No right subtree to handle
          switch (entries.getOpt(i)) {
            case (null) (); // Removed last entry, nothing to adjust
            case (?nextEntry) {
              // Adjust next entry's prefixLength and keySuffix
              let nextKey = reconstructKey(node.entries, i + 1, ?entryKey);
              let (newSuffix, newPrefixLength) = switch (prevKeyOrNull) {
                case (?prevKey) {
                  let prefixLength = findCommonPrefixLength(prevKey, nextKey);
                  let suffix = Array.sliceToArray(nextKey, prefixLength, nextKey.size());
                  (suffix, prefixLength);
                };
                case (null) {
                  (nextKey, 0);
                };
              };
              entries.put(i, { nextEntry with keySuffix = newSuffix; prefixLength = newPrefixLength });
            };
          };
        };
      };

      let updatedNode = {
        node with
        entries = DynamicArray.toArray(entries)
      };

      let newNodes = addNode(mst.nodes, updatedNode);

      return #ok({
        updatedNodeData = newNodes;
        removedEntryValue = removedEntry.valueCID;
      });
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

        switch (removeRecursive(mst, subtree, keyBytes)) {
          case (#ok({ updatedNodeData = { newNodes; newNodeCID }; removedEntryValue = removedValue })) {
            let ?newSubtreeNode = PureMap.get(newNodes, CIDBuilder.compare, newNodeCID) else Runtime.unreachable();

            // Check if subtree is now empty
            let newSubtreeCIDOrNull = if (newSubtreeNode.entries.size() == 0 and newSubtreeNode.leftSubtreeCID == null) {
              null;
            } else {
              ?newNodeCID;
            };

            #ok({
              updatedNodeData = updateNodeSubtreeAndAdd(newNodes, node, searchPos, newSubtreeCIDOrNull);
              removedEntryValue = removedValue;
            });
          };
          case (#err(e)) #err(e);
        };
      };
      case (null) #err("Key not found");
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

  private func keyToText(key : [Nat8]) : Text {
    switch (Text.decodeUtf8(Blob.fromArray(key))) {
      case (?t) t;
      case (null) Runtime.trap("Invalid entry key is not valid UTF-8: " # debug_show (key));
    };
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
