import type { Principal } from '@dfinity/principal';
import type { ActorMethod } from '@dfinity/agent';
import type { IDL } from '@dfinity/candid';

export interface CreatePlcRequest {
  'services' : Array<PlcService>,
  'alsoKnownAs' : Array<string>,
}
export interface InitializeRequest {
  'plc' : PlcKind,
  'hostname' : string,
  'handlePrefix' : [] | [string],
}
export type PlcKind = { 'id' : string } |
  { 'car' : Uint8Array | number[] } |
  { 'new' : CreatePlcRequest };
export interface PlcService {
  'id' : string,
  'endpoint' : string,
  'type' : string,
}
export type Result = { 'ok' : null } |
  { 'err' : string };
export interface _SERVICE {
  'deploy' : ActorMethod<[[] | [Principal], InitializeRequest], Result>,
  'retryFailedInitialization' : ActorMethod<
    [Principal, InitializeRequest],
    Result
  >,
}
export declare const idlFactory: IDL.InterfaceFactory;
export declare const init: (args: { IDL: typeof IDL }) => IDL.Type[];
