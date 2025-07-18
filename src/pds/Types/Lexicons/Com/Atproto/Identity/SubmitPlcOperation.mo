import DagCbor "mo:dag-cbor";
import Json "mo:json";
import Result "mo:new-base/Result";
import JsonDagCborMapper "../../../../../JsonDagCborMapper";

module {

    /// Request type for com.atproto.identity.submitPlcOperation
    public type Request = {
        /// The PLC operation to submit
        operation : DagCbor.Value;
    };

    /// This endpoint has no response output (just validates and submits)

    public func fromJson(json : Json.Json) : Result.Result<Request, Text> {
        let operationJson = switch (Json.get(json, "operation")) {
            case (?op) op;
            case (null) return #err("Missing required field: operation");
        };

        let operation = JsonDagCborMapper.toDagCbor(operationJson);

        #ok({
            operation = operation;
        });
    };
};
