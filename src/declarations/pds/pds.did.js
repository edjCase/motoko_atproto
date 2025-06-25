export const idlFactory = ({ IDL }) => {
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
  const ServerInfo = IDL.Record({
    'did' : IDL.Text,
    'privacyPolicy' : IDL.Text,
    'contactEmailAddress' : IDL.Text,
    'inviteCodeRequired' : IDL.Bool,
    'availableUserDomains' : IDL.Vec(IDL.Text),
    'version' : IDL.Text,
    'termsOfService' : IDL.Text,
  });
  const Result = IDL.Variant({ 'ok' : IDL.Null, 'err' : IDL.Text });
  return IDL.Service({
    'buildPlcRequest' : IDL.Func([], [Result_1], []),
    'getUrls' : IDL.Func([], [IDL.Vec(IDL.Text)], ['query']),
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
  });
};
export const init = ({ IDL }) => { return []; };
