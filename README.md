# UndoManager
Handles UnDo and ReDo for a UI with multiple inputs

Stop and Start can be used to pause recording during batch operations

UnDo and ReDo reinstate prior states

UndoAvailable and RedoAvailable return true if UnDo/ReDo data is available

Add to variables:
-----------------

  UIControls: TControlArray;

Add to Form creation
--------------------

  UIControls := [Edit1, ComboBox1, Edit2, Memo1];
  UndoManager := TUndoManager.Create;
  UndoManager.AddFullState(UIControls);

AddFullState() will create a (here a first) snapshot of the listed controls

Add to the control.onChange methode
-----------------------------------

  var Ctrl: TWinControl;

  if UndoManager.Restoring then Exit;
  Ctrl := TWinControl(Sender);
  UndoManager.AddState(Ctrl);

Use as
------

  UndoManager.Redo;
  UndoManager.Undo;

  
