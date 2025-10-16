import Debug "mo:core@1/Debug";
import Runtime "mo:core@1/Runtime";
import Blob "mo:core@1/Blob";
import Iter "mo:core@1/Iter";
import { test } "mo:test";
import CAR "mo:car@1";
import CarUtil "../src/pds/CarUtil";
import PureMap "mo:core@1/pure/Map";

test(
  "buildRepository",
  func() : () {
    let rawCarFile : Blob = "\3a\a2\65\72\6f\6f\74\73\81\d8\2a\58\25\00\01\71\12\20\ae\35\dd\20\f3\d5\46\1e\5f\9a\13\40\e5\3a\a4\a7\d4\7b\73\7e\5b\5f\c3\41\5d\64\89\6b\fb\da\cc\26\67\76\65\72\73\69\6f\6e\01\da\01\01\71\12\20\ae\35\dd\20\f3\d5\46\1e\5f\9a\13\40\e5\3a\a4\a7\d4\7b\73\7e\5b\5f\c3\41\5d\64\89\6b\fb\da\cc\26\a5\63\64\69\64\78\20\64\69\64\3a\70\6c\63\3a\73\64\70\76\36\74\72\6f\7a\37\6f\7a\72\6a\66\32\74\69\74\64\74\63\64\32\63\72\65\76\6d\35\36\34\69\61\62\79\73\6f\77\6f\32\32\63\73\69\67\58\40\98\bf\ab\dd\b6\5f\9c\0a\4e\7a\ca\e1\f2\a4\8a\c2\a6\ef\f4\1f\5f\10\38\12\94\01\01\ad\d5\3f\9a\b7\6e\67\92\e8\ac\27\aa\04\b3\9a\11\8c\1a\ac\36\3b\53\cf\0d\a2\02\52\6c\1c\2d\3b\60\e0\89\23\16\19\64\64\61\74\61\d8\2a\58\25\00\01\71\12\20\9d\fe\fe\61\dd\76\ea\3d\ca\e5\02\38\80\b0\83\79\d5\7a\df\20\48\2d\6f\db\e2\75\92\89\f6\47\67\7b\67\76\65\72\73\69\6f\6e\03";
    let carFile = switch (CAR.fromBytes(rawCarFile.vals())) {
      case (#err(err)) Runtime.trap("Error reading CAR file: " # err);
      case (#ok(carFile)) carFile;
    };
    switch (CarUtil.buildRepository(carFile)) {
      case (#err(err)) Runtime.trap("Error building repository: " # err);
      case (#ok((rootCid, repo))) {
        Debug.print("Root CID: " # debug_show (rootCid));
        let prettyRepo = {
          repo with
          commits = PureMap.entries(repo.commits) |> Iter.toArray(_);
          records = PureMap.entries(repo.records) |> Iter.toArray(_);
          blobs = PureMap.entries(repo.blobs) |> Iter.toArray(_);
          nodes = PureMap.entries(repo.nodes) |> Iter.toArray(_);
        };
        Debug.print("Repo: " # debug_show (prettyRepo));
      };
    };
  },
);
