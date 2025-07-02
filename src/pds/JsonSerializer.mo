import Text "mo:base/Text";
import Iter "mo:base/Iter";
import HashMap "mo:base/HashMap";
import Result "mo:base/Result";
import XrpcRouter "./XrpcRouter";
import WellKnownRouter "./WellKnownRouter";
import RouterMiddleware "mo:liminal/Middleware/Router";
import CompressionMiddleware "mo:liminal/Middleware/Compression";
import CORSMiddleware "mo:liminal/Middleware/CORS";
import JWTMiddleware "mo:liminal/Middleware/JWT";
import Liminal "mo:liminal";
import App "mo:liminal/App";
import Router "mo:liminal/Router";
import Debug "mo:new-base/Debug";
import RepositoryHandler "Handlers/RepositoryHandler";
import ServerInfoHandler "Handlers/ServerInfoHandler";
import KeyHandler "Handlers/KeyHandler";
import ServerInfo "Types/ServerInfo";
import Error "mo:new-base/Error";
import Array "mo:new-base/Array";
import Blob "mo:new-base/Blob";
import Sha256 "mo:sha2/Sha256";
import Json "mo:json";
import BaseX "mo:base-x-encoder";
import TextX "mo:xtended-text/TextX";
import DIDModule "./DID";
import DagCbor "mo:dag-cbor";

module {

    public func signedPlcRequest(request : DIDModule.SignedPlcRequest) : Text {
        func toTextArray(arr : [Text]) : [Json.Json] {
            arr |> Array.map(_, func(item : Text) : Json.Json = #string(item));
        };

        let verificationMethodsJsonObj : Json.Json = #object_(
            request.verificationMethods
            |> Array.map<(Text, Text), (Text, Json.Json)>(
                _,
                func(pair : (Text, Text)) : (Text, Json.Json) = (pair.0, #string(pair.1)),
            )
        );

        let servicesJsonObj : Json.Json = #object_(
            request.services
            |> Array.map<DIDModule.PlcService, (Text, Json.Json)>(
                _,
                func(service : DIDModule.PlcService) : (Text, Json.Json) = (
                    service.name,
                    #object_([
                        ("type", #string(service.type_)),
                        ("endpoint", #string(service.endpoint)),
                    ]),
                ),
            )
        );

        let jsonObj : Json.Json = #object_([
            ("type", #string(request.type_)),
            ("rotationKeys", #array(request.rotationKeys |> toTextArray(_))),
            ("verificationMethods", verificationMethodsJsonObj),
            ("alsoKnownAs", #array(request.alsoKnownAs |> toTextArray(_))),
            ("services", servicesJsonObj),
            (
                "prev",
                switch (request.prev) {
                    case (?prev) #string(prev);
                    case (null) #null_;
                },
            ),
            ("sig", #string(BaseX.toBase64(request.signature.vals(), #url({ includePadding = false })))),
        ]);

        Json.stringify(jsonObj, null);
    };
};
