unit ALoggerUnit;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  ToStringFunction = function: widestring;

procedure FMTWriteLn(const Fmt: ansistring; const Args: array of const);
procedure FMTDebugLn(const Fmt: ansistring; const Args: array of const;
  Verbosity: integer = 0);
procedure DebugLn(const Msg: ansistring; Verbosity: integer = 0);
procedure DebugLnEveryN(N: integer; const Msg: ansistring; Verbosity: integer = 0);
procedure FMTDebugLnEveryN(N: integer; const Fmt: ansistring;
  const Args: array of const; Verbosity: integer = 0);
procedure FatalLn(const Msg: ansistring);
procedure FmtFatalLn(const Fmt: ansistring; const Args: array of const);
procedure FmtFatalLnIFFalse(Value: boolean; const Fmt: ansistring;
  const Args: array of const);
procedure InitLogger(DebugLvl: integer);

implementation

uses
  SyncUnit, OnceUnit, lnfodwrf,
  GenericCollectionUnit;

var
  Mutex4LineInfo: TMutex;
  PrintOnce: TOnce;

type

  { TALogger }

  TALogger = class(TObject)
  private
    FDebug: integer;

  public
    property Debug: integer read FDebug write FDebug;
    constructor Create(DbgLevel: integer);
    destructor Destroy; override;


    procedure FMTWriteLn(const Fmt: ansistring; const Args: array of const);
    procedure FMTDebugLn(const Fmt: ansistring; const Args: array of const;
      Verbosity: integer = 0);
    procedure DebugLn(const Msg: ansistring; Verbosity: integer = 0);
    procedure DebugLnEveryN(N: integer; const Msg: ansistring;
      Verbosity: integer = 0);
    procedure FMTDebugLnEveryN(N: integer; const Fmt: ansistring;
      const Args: array of const; Verbosity: integer = 0);
    procedure FatalLn(const Msg: ansistring);
    procedure FmtFatalLn(const Fmt: ansistring; const Args: array of const);
    procedure FmtFatalLnIFFalse(Value: boolean; const Fmt: ansistring;
      const Args: array of const);

  end;



procedure GetParentLineInfo(var Filename: ansistring; var LineNumber: integer;
  Depth: integer = 0);
var
  CallerAddress, bp: CodePointer;
  Func, Source: shortstring;
  i: integer;
begin
  Filename := 'UNKNOWN';
  LineNumber := -1;

  // Get the current frame
  bp := get_frame;
  CallerAddress := nil;

  // Walk up the stack to the requested Depth
  // Depth = 0 gets the immediate caller of GetParentLineInfo
  for i := 0 to Depth do
  begin
    if bp = nil then
      Exit;
    CallerAddress := get_caller_addr(bp);
    bp := get_caller_frame(bp);
  end;

  if CallerAddress = nil then
  begin
    PrintOnce.Run;
    Exit;
  end;

  Func := '';
  Source := '';

  Mutex4LineInfo.Lock();

  if not GetLineInfo(CodePtrUInt(CallerAddress), Func, Source, LineNumber) then
  begin
    PrintOnce.Run;
  end;

  Mutex4LineInfo.Unlock();

  if Source <> '' then
  begin
    Filename := ExtractFileName(Source);
  end;
end;

var
  MutexWriteLn: TMutex;

procedure _WriteLn(const Message: ansistring);
begin
  MutexWriteLn.Lock;
  System.Writeln(StdErr, Message);
  Flush(StdErr);

  MutexWriteLn.Unlock;

end;

procedure _DebugLn(const Filename: ansistring; LineNumber: integer;
  const Fmt: ansistring; const Args: array of const);
var
  Message: ansistring;
begin
  Message := Format(Fmt, Args);
  if (Filename <> 'UNKNOWN') and (LineNumber <> -1) then
    _Writeln(Format('%d-%s-%s:%d] %s', [ThreadID, DateTimeToStr(Now),
      Filename, LineNumber, Message]))
  else
    _Writeln(Format('%u-%s] %s', [PtrUInt(ThreadID), DateTimeToStr(Now), Message]));
end;

procedure TALogger.DebugLn(const Msg: ansistring; Verbosity: integer);
var
  Filename: ansistring;
  LineNumber: integer;
begin
  if Self.Debug < Verbosity then
    Exit;

  GetParentLineInfo(Filename, LineNumber, 2);
  _DebugLn(Filename, LineNumber, '%s', [Msg]);
end;

procedure TALogger.FMTDebugLn(const Fmt: ansistring; const Args: array of const;
  Verbosity: integer);
var
  Filename: ansistring;
  LineNumber: integer;
begin
  if Self.Debug < Verbosity then
    Exit;

  GetParentLineInfo(Filename, LineNumber, 2);
  _DebugLn(Filename, LineNumber, Fmt, Args);

end;

type
  TLineInfoIntegerMap = specialize TMap<ansistring, integer>;

var
  Counters: TLineInfoIntegerMap;
  Mutex4Counters: TMutex;

procedure _DebugLnEveryN(const Filename: ansistring; LineNumber: integer;
  N: integer; const Fmt: ansistring; const Args: array of const;
  Verbosity: integer; Depth: integer);
var
  LineInfo: ansistring;
  Value: integer;
  b: boolean;
begin
  LineInfo := Format('%s:%d', [Filename, LineNumber]);

  Mutex4Counters.Lock;

  if not Counters.TryGetData(LineInfo, Value) then
  begin
    Counters.Add(LineInfo, 0);
    Value := 0;

  end;

  b := Value mod N = 0;
  Counters.AddOrUpdateData(LineInfo, Value + 1);
  Mutex4Counters.Unlock;

  if b then
  begin
    _Writeln(Format('%d-%s-%s:%d] %s', [ThreadID, DateTimeToStr(Now),
      Filename, LineNumber, Format(Fmt, Args)]));

  end;

end;

procedure TALogger.DebugLnEveryN(N: integer; const Msg: ansistring; Verbosity: integer);
var
  Filename: ansistring;
  LineNumber: integer;
begin
  if Self.Debug < Verbosity then
    Exit;

  GetParentLineInfo(Filename, LineNumber, 2);
  _DebugLnEveryN(Filename, LineNumber, N, '%s', [Msg], Verbosity, 2);

end;

procedure TALogger.FMTDebugLnEveryN(N: integer; const Fmt: ansistring;
  const Args: array of const; Verbosity: integer);
var
  Filename: ansistring;
  LineNumber: integer;
begin
  if Self.Debug < Verbosity then
    Exit;

  GetParentLineInfo(Filename, LineNumber, 2);
  _DebugLnEveryN(Filename, LineNumber, N, Fmt, Args, Verbosity, 2);

end;

procedure _FatalLn(const FileName: ansistring; LineNumber: integer;
  const Msg: ansistring);
begin
  _Writeln(Format('%d-%s-%s:%d] %s', [ThreadID, DateTimeToStr(Now),
    Filename, LineNumber, Msg]));

  Halt(1);

end;

procedure TALogger.FatalLn(const Msg: ansistring);
var
  Filename: ansistring;
  LineNumber: integer;
begin
  Filename := '';
  LineNumber := 0;
  GetParentLineInfo(Filename, LineNumber, 2);
  _FatalLn(Filename, LineNumber, Msg);

end;


procedure TALogger.FmtFatalLn(const Fmt: ansistring; const Args: array of const);
var
  Filename: ansistring;
  LineNumber: integer;
begin
  GetParentLineInfo(Filename, LineNumber, 2);
  _FatalLn(Filename, LineNumber, Format(Fmt, Args));

end;

procedure TALogger.FmtFatalLnIFFalse(Value: boolean; const Fmt: ansistring;
  const Args: array of const);
var
  Filename: ansistring;
  LineNumber: integer;
begin
  if Value then
    Exit;

  GetParentLineInfo(Filename, LineNumber, 2);
  _FatalLn(Filename, LineNumber, Format(Fmt, Args));

end;

var
  Logger: TALogger;

function GetLogger: TALogger;
begin
  Result := Logger;

end;

{ TALogger }

constructor TALogger.Create(DbgLevel: integer);
begin
  inherited Create;

  FDebug := DbgLevel;
end;

destructor TALogger.Destroy;
begin
  inherited Destroy;

end;

procedure TALogger.FMTWriteLn(const Fmt: ansistring; const Args: array of const);
begin
  System.WriteLn(Format(Fmt, Args));

end;

procedure FMTWriteLn(const Fmt: ansistring; const Args: array of const);
begin
  GetLogger.FMTWriteLn(Fmt, Args);
end;

procedure FMTDebugLn(const Fmt: ansistring; const Args: array of const;
  Verbosity: integer);
begin
  GetLogger.FMTDebugLn(Fmt, Args, Verbosity);
end;

procedure DebugLn(const Msg: ansistring; Verbosity: integer);
begin
  GetLogger.DebugLn(Msg, Verbosity);

end;

procedure DebugLnEveryN(N: integer; const Msg: ansistring; Verbosity: integer);
begin
  GetLogger.DebugLnEveryN(N, Msg, Verbosity);

end;

procedure FMTDebugLnEveryN(N: integer; const Fmt: ansistring;
  const Args: array of const; Verbosity: integer);
begin
  GetLogger.FMTDebugLnEveryN(N, Fmt, Args, Verbosity);

end;

procedure FatalLn(const Msg: ansistring);
begin
  GetLogger.FatalLn(Msg);

end;

procedure FmtFatalLn(const Fmt: ansistring; const Args: array of const);
begin
  GetLogger.FMTDebugLn(Fmt, Args);

end;

procedure FmtFatalLnIFFalse(Value: boolean; const Fmt: ansistring;
  const Args: array of const);
var
  Filename: ansistring;
  LineNumber: integer;
begin
  if Value then
    Exit;

  GetParentLineInfo(Filename, LineNumber, 2);
  _FatalLn(Filename, LineNumber, Format(Fmt, Args));

end;

procedure FmtFatalLnIFFalse(Value: boolean; const Fmt: ansistring;
  const ArgFuncs: array of ToStringFunction);
var
  i: integer;
  Args: array of widestring;
begin
  if Value then
    Exit;

  SetLength(Args, Length(ArgFuncs));
  for i := 0 to High(ArgFuncs) do
    Args[i] := ArgFuncs[i]();

end;

procedure InitLogger(DebugLvl: integer);
begin
  Logger := TALogger.Create(DebugLvl);

end;

function Format(const Fmt: ansistring; Args: array of const): ansistring;
begin
  Result := SysUtils.Format(Fmt, Args);
end;

procedure PrintError(Arguments: TPtrArray);
begin
  WriteLn(StdErr, 'Please make sure the code is compiled with -g');

end;

initialization
  Mutex4LineInfo := TMutex.Create;
  Mutex4Counters := TMutex.Create;
  MutexWriteLn := TMutex.Create;
  Counters := TLineInfoIntegerMap.Create;
  PrintOnce := TOnce.Create(@PrintError, nil);
  Logger := nil;

finalization
  Logger.Free;

  Counters.Free;
  Mutex4LineInfo.Free;
  Mutex4Counters.Free;
  MutexWriteLn.Free;
  PrintOnce.Free;

end.
