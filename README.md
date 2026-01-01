# Motoko AT Protocol Library

[![MOPS](https://img.shields.io/badge/MOPS-atproto-blue)](https://mops.one/atproto)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/edjCase/motoko_atproto/blob/main/LICENSE)

A comprehensive Motoko library for building AT Protocol (ATProto) applications on the Internet Computer. This library provides core data structures, repository management, cryptographic operations, and utilities for implementing Personal Data Servers (PDS) and other AT Protocol services.

## Package

### MOPS

```bash
mops add atproto
```

To set up MOPS package manager, follow the instructions from the [MOPS Site](https://mops.one)

## Overview

The AT Protocol (Authenticated Transfer Protocol) is the foundation for decentralized social networks like Bluesky. This library provides Motoko implementations of:

- **Repository Management**: Full IPLD-based repository with commit history and Merkle Search Trees
- **Identity & DIDs**: AT URI parsing and DID document handling
- **Cryptographic Primitives**: CID generation, DAG-CBOR encoding, and commit signing
- **Data Structures**: Blob references, strong references, and lexicon validators
- **Merkle Search Trees**: Efficient key-value storage with cryptographic proofs

## Quick Start

### Example 1: Working with AT URIs

```motoko
import AtUri "mo:atproto/AtUri";
import DID "mo:did";

// Create an AT URI
let uri : AtUri.AtUri = {
  authority = #plc(myPlcDid);
  collection = ?{
    id = "app.bsky.feed.post";
    recordKey = ?"3jzfcijpj2z2a";
  };
};

// Convert to text representation
let uriText = AtUri.toText(uri);
// Result: "at://did:plc:xxx/app.bsky.feed.post/3jzfcijpj2z2a"

// Parse from text
switch (AtUri.fromText("at://alice.bsky.social/app.bsky.feed.post/123")) {
  case (?parsedUri) {
    Debug.print("Successfully parsed AT URI");
  };
  case (null) {
    Debug.print("Invalid AT URI format");
  };
};
```

### Example 2: Creating a Repository

```motoko
import Repository "mo:atproto/Repository";
import DID "mo:did";
import TID "mo:tid";
import Result "mo:core/Result";

// Initialize an empty repository
let did = myPlcDid; // Your PLC DID
let rev = TID.now(); // Current timestamp
let signFunc = func(data : Blob) : async* Result.Result<Blob, Text> {
  // Your signing implementation
};

let repo = await* Repository.empty(did, rev, signFunc);

// Create a new record
let createOp : Repository.WriteOperation = #create({
  key = {
    collection = "app.bsky.feed.post";
    recordKey = "3jzfcijpj2z2a";
  };
  value = myPostRecord; // DAG-CBOR encoded value
});

// Apply the operation
switch (await* Repository.applyWrites(repo, [createOp], signFunc)) {
  case (#ok({ repository = newRepo; results })) {
    Debug.print("Record created successfully");
  };
  case (#err(error)) {
    Debug.print("Error: " # error);
  };
};
```

### Example 3: Merkle Search Tree Operations

```motoko
import MST "mo:atproto/MerkleSearchTree";
import CID "mo:cid";

// Create an empty Merkle Search Tree
let mst = MST.empty();

// Add entries
let recordCid = myCidValue;
switch (MST.add(mst, "app.bsky.feed.post/123", recordCid)) {
  case (#ok(newMst)) {
    Debug.print("Entry added to MST");
    
    // Retrieve the entry
    switch (MST.get(newMst, "app.bsky.feed.post/123")) {
      case (?cid) {
        Debug.print("Found CID: " # CID.toText(cid));
      };
      case (null) {
        Debug.print("Entry not found");
      };
    };
  };
  case (#err(error)) {
    Debug.print("Error: " # error);
  };
};
```

### Example 4: Working with Commits

```motoko
import Commit "mo:atproto/Commit";
import CIDBuilder "mo:atproto/CIDBuilder";
import TID "mo:tid";

// Create an unsigned commit
let unsignedCommit : Commit.UnsignedCommit = {
  did = myPlcDid;
  version = 3;
  data = mstRootCid; // CID of MST root
  rev = TID.now();
  prev = ?previousCommitCid;
};

// Generate CID for the unsigned commit
let commitCid = CIDBuilder.fromUnsignedCommit(unsignedCommit);

// Sign the commit
let signature = await signData(commitBlob);
let signedCommit : Commit.Commit = {
  did = unsignedCommit.did;
  version = unsignedCommit.version;
  data = unsignedCommit.data;
  rev = unsignedCommit.rev;
  prev = unsignedCommit.prev;
  sig = signature;
};
```

### Example 5: Blob References

```motoko
import BlobRef "mo:atproto/Lexicons/BlobRef";
import CID "mo:cid";
import Json "mo:json";

// Create a blob reference
let blobRef : BlobRef.BlobRef = {
  ref = blobCid;
  mimeType = "image/jpeg";
  size = 245678;
};

// Convert to JSON for AT Protocol messages
let blobJson = BlobRef.toJson(blobRef);
// Result: {"$type": "blob", "ref": {"$link": "..."}, "mimeType": "image/jpeg", "size": 245678}
```

## Core Components

### Repository

The `Repository` module provides a complete implementation of an AT Protocol repository with:

- **Write Operations**: Create, update, and delete records
- **Commit History**: Full history of all repository changes
- **Record Storage**: Efficient storage and retrieval of DAG-CBOR encoded records
- **Export/Import**: CAR file generation for repository synchronization
- **Validation**: Ensures repository integrity and proper commit chains

### Merkle Search Tree

A specialized data structure for efficient, cryptographically verifiable key-value storage:

- **Ordered Storage**: Keys are stored in lexicographic order
- **Cryptographic Proofs**: Each node has a CID for verification
- **Efficient Updates**: Minimal tree modifications on changes
- **Range Queries**: Support for prefix-based searches
- **Historical Nodes**: Optional retention of previous tree states

### AT URIs

Parse and construct AT Protocol URIs with support for:

- **Handle Authorities**: `at://alice.bsky.social/...`
- **DID Authorities**: `at://did:plc:xyz.../...`
- **Collection Paths**: References to specific collections
- **Record Keys**: Direct links to individual records

### DID Documents

Work with Decentralized Identifier documents:

- **Verification Methods**: Public key management
- **Service Endpoints**: PDS and other service discovery
- **JSON Serialization**: Standard DID document format
- **Key References**: Support for key rotation

## Use Cases

• **Personal Data Servers**: Build PDS implementations for the AT Protocol
• **Social Media Clients**: Create Bluesky and AT Protocol clients
• **Repository Management**: Implement repository operations for any AT Protocol service
• **Identity Services**: Handle DID resolution and verification
• **Data Synchronization**: Export and import repositories using CAR files
• **Federated Services**: Build relays, app views, and other AT Protocol infrastructure
• **DAO Social Presence**: Enable organizations to manage collective social media identities

## API Reference

### Core Types

```motoko
// AT URI structure
public type AtUri = {
  authority : { #handle : Text; #plc : DID.Plc.DID };
  collection : ?{
    id : Text;
    recordKey : ?Text;
  };
};

// Repository metadata
public type MetaData = {
  head : CID.CID;
  rev : TID.TID;
  active : Bool;
  status : ?Text;
};

// Write operations
public type WriteOperation = {
  #create : { key : Key; value : DagCbor.Value };
  #update : { key : Key; value : DagCbor.Value };
  #delete : { key : Key };
};

// Commit structure
public type Commit = {
  did : DID.Plc.DID;
  version : Nat;
  data : CID.CID;
  rev : TID.TID;
  prev : ?CID.CID;
  sig : Blob;
};
```

### Repository Functions

```motoko
// Create an empty repository
public func empty(
  did : DID.Plc.DID,
  rev : TID.TID,
  signFunc : (Blob) -> async* Result.Result<Blob, Text>
) : async* Result.Result<Repository, Text>;

// Apply write operations
public func applyWrites(
  repo : Repository,
  writes : [WriteOperation],
  signFunc : (Blob) -> async* Result.Result<Blob, Text>
) : async* Result.Result<{
  repository : Repository;
  results : [WriteResult];
}, Text>;

// Get a record by key
public func getRecord(
  repo : Repository,
  key : Key
) : ?RecordData;

// List all records in a collection
public func listRecords(
  repo : Repository,
  collection : Text
) : [(Text, RecordData)];

// Export repository as CAR file
public func exportCar(
  repo : Repository,
  since : ?TID.TID
) : Result.Result<Blob, Text>;
```

### Merkle Search Tree Functions

```motoko
// Create an empty MST
public func empty() : MerkleSearchTree;

// Add an entry (fails if key exists)
public func add(
  mst : MerkleSearchTree,
  key : Text,
  value : CID.CID
) : Result.Result<MerkleSearchTree, Text>;

// Put an entry (creates or updates)
public func put(
  mst : MerkleSearchTree,
  key : Text,
  value : CID.CID
) : Result.Result<MerkleSearchTree, Text>;

// Remove an entry
public func remove(
  mst : MerkleSearchTree,
  key : Text
) : Result.Result<(MerkleSearchTree, CID.CID), Text>;

// Get an entry
public func get(
  mst : MerkleSearchTree,
  key : Text
) : ?CID.CID;

// Validate MST structure
public func validate(
  mst : MerkleSearchTree
) : Result.Result<(), Text>;
```

### AT URI Functions

```motoko
// Convert AT URI to text
public func toText(uri : AtUri) : Text;

// Parse AT URI from text
public func fromText(path : Text) : ?AtUri;
```

### CID Builder Functions

```motoko
// Create CID from blob
public func fromBlob(blob : Blob) : CID.CID;

// Create CID from commit
public func fromCommit(commit : Commit) : CID.CID;

// Create CID from MST node
public func fromMSTNode(node : MerkleNode.Node) : CID.CID;

// Create CID from DAG-CBOR value
public func fromDagCbor(cbor : DagCbor.Value) : CID.CID;
```

## Project Structure

```
src/
├── AtUri.mo                    # AT Protocol URI parsing and construction
├── Repository.mo               # Repository management and operations
├── MerkleSearchTree.mo         # Merkle Search Tree implementation
├── MerkleNode.mo              # MST node structure
├── Commit.mo                   # Commit structures
├── CIDBuilder.mo              # CID generation utilities
├── DagCborBuilder.mo          # DAG-CBOR encoding helpers
├── JsonDagCborMapper.mo       # JSON to DAG-CBOR conversion
├── DIDDocument.mo             # DID document handling
└── Lexicons/
    ├── BlobRef.mo             # Blob reference types
    ├── StrongRef.mo           # Strong reference types
    ├── LexiconValidator.mo    # Schema validation
    └── App/Bsky/...           # Bluesky lexicon types
    └── Com/Atproto/...        # AT Protocol lexicon types
```

## Testing

```bash
mops test
```

## Real-World Usage

This library is used by:

- **[motoko_atproto_pds](https://github.com/edjCase/motoko_atproto_pds)**: A complete PDS implementation for the Internet Computer, enabling DAOs and organizations to manage AT Protocol identities and post to Bluesky

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## Dependencies

This library builds upon several excellent Motoko packages:

- **[cid](https://mops.one/cid)**: Content Identifier implementation
- **[dag-cbor](https://mops.one/dag-cbor)**: DAG-CBOR encoding/decoding
- **[did](https://mops.one/did)**: Decentralized Identifier utilities
- **[tid](https://mops.one/tid)**: Timestamp Identifier generation
- **[sha2](https://mops.one/sha2)**: SHA-256 hashing
- **[json](https://mops.one/json)**: JSON encoding/decoding
- **[core](https://mops.one/core)**: Core Motoko utilities

## Resources

- [AT Protocol Documentation](https://atproto.com/)
- [Bluesky Social](https://bsky.app/)
- [Internet Computer Documentation](https://internetcomputer.org/docs)
- [Motoko Documentation](https://internetcomputer.org/docs/current/motoko/main/motoko)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
