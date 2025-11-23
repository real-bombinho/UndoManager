unit UndoManager;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls

  ,Dialogs // for showmessage / debugging
  ;

type

  TControlArray = array of TControl;

  TTextChange = record
    Pos: Integer;        // position in text where change starts
    Deleted: string;     // text removed
    Inserted: string;    // text added
  end;

  { Base class for all undo records }
  TUndoBase = class
  public
    procedure Restore; virtual; abstract;
  end;

  { TUndoFullRecord }
  TUndoFullRecord = class(TUndoBase)
  private
    FControls: array of TControl;   // references to controls
    FValues: array of string;       // snapshot values
  public
    Time: TDateTime;
    constructor Create(const AControls: TControlArray);
    procedure Restore; override;
  end;

  { TUndoItem }

  TUndoItem = class(TUndoBase)
  private
    FControl: TWinControl;
    FChange: TTextChange;
    class function GetText(AControl: TWinControl): string; static;
  public
    class procedure SetControlText(AControl: TWinControl; const AText: string; CaretPos: Integer = 0); static;
    constructor Create(AControl: TWinControl; const OldText: string);
    procedure Restore; override;              // redo
    procedure RestorePrior; // undo
    //property Control: TWinControl read FControl;
    //property Change: TTextChange read FChange;
  end;

  { TUndoManager }
  TUndoManager = class
  private
    FStates: TList;       // list of TUndoBase
    FIndex: Integer;
    FRestoring: Boolean;  // guard flag
    procedure TruncateFuture;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddState(AControl: TWinControl);
    procedure AddFullState(const AControls: TControlArray);
    property Restoring: Boolean read FRestoring;
    procedure Undo;
    procedure Redo;
    procedure Stop;
    procedure Start;
    function LastValue(AControl: TWinControl): string;
    function UndoAvailable: boolean;
    function RedoAvailable: boolean;
  end;

implementation

{ TUndoFullRecord }

constructor TUndoFullRecord.Create(const AControls: TControlArray);
var
  I: Integer;
begin
  Time := Now;
  SetLength(FControls, Length(AControls));
  SetLength(FValues, Length(AControls));

  for I := 0 to High(AControls) do
  begin
    FControls[I] := AControls[I];  // store pointer
    if AControls[I] is TEdit then
      FValues[I] := TEdit(AControls[I]).Text
    else if AControls[I] is TMemo then
      FValues[I] := TMemo(AControls[I]).Text
    else if AControls[I] is TComboBox then
      FValues[I] := TComboBox(AControls[I]).Text
    else
      FValues[I] := '';
  end;
end;

procedure TUndoFullRecord.Restore;
var
  I: Integer;
begin
  for I := 0 to High(FControls) do
  begin
    if FControls[I] is TEdit then
      TEdit(FControls[I]).Text := FValues[I]
    else if FControls[I] is TMemo then
    begin
      TMemo(FControls[I]).Text := FValues[I];
    end
    else if FControls[I] is TComboBox then
      TComboBox(FControls[I]).Text := FValues[I];
  end;
end;

{ TUndoItem }

// getText extracts the current text from the control

class function TUndoItem.GetText(AControl: TWinControl): string;
begin
  if AControl is TEdit then
    result := TEdit(AControl).Text
  else if AControl is TMemo then
    result := TMemo(AControl).Text
  else if AControl is TComboBox then
    result := TComboBox(AControl).Text;
end;

class procedure TUndoItem.SetControlText(AControl: TWinControl; const AText: string; CaretPos: Integer);
begin
  if AControl is TEdit then
  begin
    TEdit(AControl).Text := AText;
    TEdit(AControl).SelStart := CaretPos;
  end
  else if AControl is TMemo then
  begin
    TMemo(AControl).Text := AText;
    TMemo(AControl).SelStart := CaretPos;
  end
  else if AControl is TComboBox then
  begin
    TComboBox(AControl).Text := AText;
    TComboBox(AControl).SelStart := CaretPos;
  end;
  AControl.SetFocus;
end;

constructor TUndoItem.Create(AControl: TWinControl; const OldText: string);
var
  NewText: string;
  Start, OldEnd, NewEnd: Integer;
begin
  FControl := AControl;
  NewText := GetText(AControl);

  // Simple diff: find common prefix/suffix
  Start := 1;
  while (Start <= Length(OldText)) and (Start <= Length(NewText)) and
        (OldText[Start] = NewText[Start]) do
    Inc(Start);

  OldEnd := Length(OldText);
  NewEnd := Length(NewText);
  while (OldEnd >= Start) and (NewEnd >= Start) and
        (OldText[OldEnd] = NewText[NewEnd]) do
  begin
    Dec(OldEnd);
    Dec(NewEnd);
  end;

  FChange.Pos := Start;
  FChange.Deleted := Copy(OldText, Start, OldEnd - Start + 1);
  FChange.Inserted := Copy(NewText, Start, NewEnd - Start + 1);
end;

procedure TUndoItem.Restore; // redo
var
  Text: string;
begin
  Text := GetText(FControl);
  Delete(Text, FChange.Pos, Length(FChange.Deleted));
  Insert(FChange.Inserted, Text, FChange.Pos);
  SetControlText(FControl, Text, FChange.Pos);
end;

procedure TUndoItem.RestorePrior; // undo
var
  Text: string;
begin
  Text := GetText(FControl);
  Delete(Text, FChange.Pos, Length(FChange.Inserted));
  Insert(FChange.Deleted, Text, FChange.Pos);
  SetControlText(FControl, Text, FChange.Pos);
end;

{ TUndoManager }

constructor TUndoManager.Create;
begin
  FStates := TList.Create;
  FIndex := -1;
end;

destructor TUndoManager.Destroy;
var
  I: Integer;
begin
  for I := 0 to FStates.Count - 1 do TUndoBase(FStates[I]).Free;
  FStates.Free;
  inherited;
end;

procedure TUndoManager.TruncateFuture;
begin
  while FStates.Count - 1 > FIndex do
  begin
    TUndoBase(FStates.Last).Free;
    FStates.Delete(FStates.Count - 1);
  end;
end;

procedure TUndoManager.AddState(AControl: TWinControl);
var
  OldText, NewText: string;
begin
  if FRestoring then Exit;

  OldText := LastValue(AControl);

  // Use TUndoItem’s GetText to read current content
  NewText := TUndoItem(nil).GetText(AControl); // or make GetText a class function

  // Skip if no change
  if NewText = OldText then
    Exit;

  TruncateFuture;
  FStates.Add(TUndoItem.Create(AControl, OldText));
  FIndex := FStates.Count - 1;
end;

procedure TUndoManager.AddFullState(const AControls: TControlArray);
begin
  TruncateFuture;
  FStates.Add(TUndoFullRecord.Create(AControls));
  FIndex := FStates.Count - 1;
end;

procedure TUndoManager.Undo;
var
  Entry: TUndoBase;
  Item: TUndoItem;
begin
  if FIndex <= 0 then Exit;

  Entry := TUndoBase(FStates[FIndex]);
  FRestoring := True;
  try
    if Entry is TUndoItem then
    begin
      Item := TUndoItem(Entry);
      Item.RestorePrior;
    end
    else if Entry is TUndoFullRecord then
    begin
      //showmessage('full entry restore');
      TUndoFullRecord(Entry).Restore;
    end;
  finally
    FRestoring := False;
  end;

  Dec(FIndex);
end;

procedure TUndoManager.Redo;
begin
  if FIndex >= FStates.Count - 1 then Exit;
  Inc(FIndex);
  FRestoring := True;
  try
    TUndoBase(FStates[FIndex]).Restore;
  finally
    FRestoring := False;
  end;
end;

procedure TUndoManager.Stop;
begin
  FRestoring := True;
end;

procedure TUndoManager.Start;
begin
  FRestoring := False;
end;

function TUndoManager.LastValue(AControl: TWinControl): string;
var
  I, J: Integer;
  Obj: TUndoBase;
  Text: string;
  Item: TUndoItem;
begin
  Result := '';

  // Step 1: find the last full snapshot before UpToIndex
  for I := FIndex downto 0 do
  begin
    Obj := TUndoBase(FStates[I]);
    if Obj is TUndoFullRecord then
    begin
      for J := 0 to High(TUndoFullRecord(Obj).FControls) do
        if TUndoFullRecord(Obj).FControls[J] = AControl then
        begin
          Text := TUndoFullRecord(Obj).FValues[J];
          Break;
        end;
      Break;
    end;
  end;

  // Step 2: apply diffs forward from that snapshot up to UpToIndex
  for J := I+1 to FIndex do
  begin
    Obj := TUndoBase(FStates[J]);
    if Obj is TUndoItem then
    begin
      Item := TUndoItem(Obj);
      if Item.FControl = AControl then
      begin
        Delete(Text, Item.FChange.Pos, Length(Item.FChange.Deleted));
        Insert(Item.FChange.Inserted, Text, Item.FChange.Pos);
      end;
    end;
  end;

  Result := Text;
end;

function TUndoManager.UndoAvailable: boolean;
begin
  result := FIndex > 0;
end;

function TUndoManager.RedoAvailable: boolean;
begin
  result := FIndex < FStates.Count - 1
end;

end.

