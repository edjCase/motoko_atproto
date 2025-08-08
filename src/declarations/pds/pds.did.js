export const idlFactory = ({ IDL }) => {
  const PlcService = IDL.Record({
    'endpoint' : IDL.Text,
    'id' : IDL.Text,
    'type' : IDL.Text,
  });
  const BuildPlcRequest = IDL.Record({
    'services' : IDL.Vec(PlcService),
    'alsoKnownAs' : IDL.Vec(IDL.Text),
  });
  const Result_1 = IDL.Variant({
    'ok' : IDL.Tuple(IDL.Text, IDL.Text),
    'err' : IDL.Text,
  });
  const Header = IDL.Tuple(IDL.Text, IDL.Text);
  const RawQueryHttpRequest = IDL.Record({
    'url' : IDL.Text,
    'method' : IDL.Text,
    'body' : IDL.Vec(IDL.Nat8),
    'headers' : IDL.Vec(Header),
    'certificate_version' : IDL.Opt(IDL.Nat16),
  });
  const StreamingToken = IDL.Vec(IDL.Nat8);
  const StreamingCallbackResponse = IDL.Record({
    'token' : IDL.Opt(StreamingToken),
    'body' : IDL.Vec(IDL.Nat8),
  });
  const StreamingCallback = IDL.Func(
      [StreamingToken],
      [StreamingCallbackResponse],
      ['query'],
    );
  const CallbackStreamingStrategy = IDL.Record({
    'token' : StreamingToken,
    'callback' : StreamingCallback,
  });
  const StreamingStrategy = IDL.Variant({
    'Callback' : CallbackStreamingStrategy,
  });
  const RawQueryHttpResponse = IDL.Record({
    'body' : IDL.Vec(IDL.Nat8),
    'headers' : IDL.Vec(Header),
    'upgrade' : IDL.Opt(IDL.Bool),
    'streaming_strategy' : IDL.Opt(StreamingStrategy),
    'status_code' : IDL.Nat16,
  });
  const RawUpdateHttpRequest = IDL.Record({
    'url' : IDL.Text,
    'method' : IDL.Text,
    'body' : IDL.Vec(IDL.Nat8),
    'headers' : IDL.Vec(Header),
  });
  const RawUpdateHttpResponse = IDL.Record({
    'body' : IDL.Vec(IDL.Nat8),
    'headers' : IDL.Vec(Header),
    'streaming_strategy' : IDL.Opt(StreamingStrategy),
    'status_code' : IDL.Nat16,
  });
  const Domain = IDL.Record({
    'name' : IDL.Text,
    'subdomains' : IDL.Vec(IDL.Text),
    'suffix' : IDL.Text,
  });
  const DID = IDL.Record({ 'identifier' : IDL.Text });
  const ServerInfo = IDL.Record({
    'domain' : Domain,
    'plcDid' : DID,
    'contactEmailAddress' : IDL.Opt(IDL.Text),
  });
  const Result = IDL.Variant({ 'ok' : IDL.Null, 'err' : IDL.Text });
  return IDL.Service({
    'buildPlcRequest' : IDL.Func([BuildPlcRequest], [Result_1], []),
    'http_request' : IDL.Func(
        [RawQueryHttpRequest],
        [RawQueryHttpResponse],
        ['query'],
      ),
    'http_request_update' : IDL.Func(
        [RawUpdateHttpRequest],
        [RawUpdateHttpResponse],
        [],
      ),
    'initialize' : IDL.Func([ServerInfo], [Result], []),
    'isInitialized' : IDL.Func([], [IDL.Bool], []),
  });
};
export const init = ({ IDL }) => { return []; };
