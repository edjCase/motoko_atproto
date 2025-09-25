export const idlFactory = ({ IDL }) => {
  const PlcService = IDL.Record({
    'id' : IDL.Text,
    'endpoint' : IDL.Text,
    'type' : IDL.Text,
  });
  const CreatePlcRequest = IDL.Record({
    'services' : IDL.Vec(PlcService),
    'alsoKnownAs' : IDL.Vec(IDL.Text),
  });
  const PlcKind = IDL.Variant({
    'id' : IDL.Text,
    'car' : IDL.Vec(IDL.Nat8),
    'new' : CreatePlcRequest,
  });
  const InitializeRequest = IDL.Record({
    'plc' : PlcKind,
    'hostname' : IDL.Text,
    'handlePrefix' : IDL.Opt(IDL.Text),
  });
  const Result = IDL.Variant({ 'ok' : IDL.Null, 'err' : IDL.Text });
  return IDL.Service({
    'deploy' : IDL.Func(
        [IDL.Opt(IDL.Principal), InitializeRequest],
        [Result],
        [],
      ),
    'retryFailedInitialization' : IDL.Func(
        [IDL.Principal, InitializeRequest],
        [Result],
        [],
      ),
  });
};
export const init = ({ IDL }) => { return []; };
