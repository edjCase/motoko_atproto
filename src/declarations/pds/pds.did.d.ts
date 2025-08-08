import type { Principal } from '@dfinity/principal';
import type { ActorMethod } from '@dfinity/agent';
import type { IDL } from '@dfinity/candid';

export interface BuildPlcRequest {
  'services': Array<PlcService>,
  'alsoKnownAs': Array<string>,
}
export interface CallbackStreamingStrategy {
  'token': StreamingToken,
  'callback': StreamingCallback,
}
export interface DID { 'identifier': string }
export interface Domain {
  'name': string,
  'subdomains': Array<string>,
  'suffix': string,
}
export type Header = [string, string];
export interface PlcService {
  'endpoint': string,
  'id': string,
  'type': string,
}
export interface RawQueryHttpRequest {
  'url': string,
  'method': string,
  'body': Uint8Array | number[],
  'headers': Array<Header>,
  'certificate_version': [] | [number],
}
export interface RawQueryHttpResponse {
  'body': Uint8Array | number[],
  'headers': Array<Header>,
  'upgrade': [] | [boolean],
  'streaming_strategy': [] | [StreamingStrategy],
  'status_code': number,
}
export interface RawUpdateHttpRequest {
  'url': string,
  'method': string,
  'body': Uint8Array | number[],
  'headers': Array<Header>,
}
export interface RawUpdateHttpResponse {
  'body': Uint8Array | number[],
  'headers': Array<Header>,
  'streaming_strategy': [] | [StreamingStrategy],
  'status_code': number,
}
export type Result = { 'ok': null } |
{ 'err': string };
export type Result_1 = { 'ok': [string, string] } |
{ 'err': string };
export interface ServerInfo {
  'domain': Domain,
  'plcDid': DID,
  'contactEmailAddress': [] | [string],
}
export type StreamingCallback = ActorMethod<
  [StreamingToken],
  StreamingCallbackResponse
>;
export interface StreamingCallbackResponse {
  'token': [] | [StreamingToken],
  'body': Uint8Array | number[],
}
export type StreamingStrategy = { 'Callback': CallbackStreamingStrategy };
export type StreamingToken = Uint8Array | number[];
export interface _SERVICE {
  'buildPlcRequest': ActorMethod<[BuildPlcRequest], Result_1>,
  'http_request': ActorMethod<[RawQueryHttpRequest], RawQueryHttpResponse>,
  'http_request_update': ActorMethod<
    [RawUpdateHttpRequest],
    RawUpdateHttpResponse
  >,
  'initialize': ActorMethod<[ServerInfo], Result>,
  'isInitialized': ActorMethod<[], boolean>,
}
export declare const idlFactory: IDL.InterfaceFactory;
export declare const init: (args: { IDL: typeof IDL }) => IDL.Type[];
