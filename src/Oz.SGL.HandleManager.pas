﻿(* Standard Generic Library (SGL) for Pascal
 * Copyright (c) 2020 Marat Shaimardanov
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *)

unit Oz.SGL.HandleManager;

interface

{$Region 'Uses'}

uses
  System.SysUtils, System.Math;

{$EndRegion}

{$T+}

{$Region 'Handles'}

type
  // Type handle
  hType = record
  const
    MaxIndex = 255;
  type
    TIndex = 0 .. MaxIndex; // 8 bits
  var
    v: TIndex;
  end;

  // Shared memory region handle
  hRegion = record
  const
    MaxIndex = 4095;
  type
    TIndex = 0 .. MaxIndex; // 12 bits
  var
    v: Cardinal;
  public
    function Index: TIndex; inline;
    // Type handle
    function Typ: hType; inline;
  end;

  // Collection handle
  hCollection = record
  const
    MaxIndex = 4095;
  type
    TIndex = 0 .. MaxIndex; // 12 bits
  var
    v: Cardinal;
  public
    constructor From(index: TIndex; counter: Byte; region: hRegion);
    function Index: TIndex; inline;
    // Shared memory region handle
    function Region: hRegion; inline;
    // Reuse counter
    function Counter: Byte; inline;
  end;

{$EndRegion}

{$Region 'TsgHandleManager: Handle manager'}

  TsgHandleManager = record
  const
    MaxNodes = 4096;
  type
    TIndex = 0 .. MaxNodes - 1;
    TNode = record
      private
        procedure SetActive(const Value: Boolean);
        procedure SetEol(const Value: Boolean);
        procedure SetNext(const Value: TIndex);
        function GetActive: Boolean;
        function GetEol: Boolean;
        function GetNext: TIndex;
        function GetCounter: Byte;
        procedure SetCounter(const Value: Byte);
      public
        ptr: Pointer;
        v: Cardinal;
        procedure Init(idx: Integer);
        property next: TIndex read GetNext write SetNext;
        property counter: Byte read GetCounter write SetCounter;
        property active: Boolean read GetActive write SetActive;
        property eol: Boolean read GetEol write SetEol;
    end;
    PNode = ^TNode;
    TNodes = array [TIndex] of TNode;
  private
    FNodes: TNodes;
    FCount: Integer;
    FRegion: hRegion;
    FUsed: TIndex;
    FAvail: TIndex;
  public
    procedure Init(region: hRegion);
    function Add(p: Pointer): hCollection;
    procedure Update(handle: hCollection; p: Pointer);
    procedure Remove(handle: hCollection);
    function Get(handle: hCollection): Pointer;
    property Count: Integer read FCount;
  end;

{$EndRegion}

implementation

{$Region 'hRegion'}

function hRegion.Index: TIndex;
begin
  Result := v and $FFF;
end;

function hRegion.Typ: hType;
begin
  Result.v := (v shr 12) and $FF;
end;

{$EndRegion}

{$Region 'hCollection'}

constructor hCollection.From(index: TIndex; counter: Byte; region: hRegion);
begin
  v := (((counter shl 12) or region.v) shl 12) or index;
end;

function hCollection.Index: TIndex;
begin
  // 2^12 - 1
  Result := v and $FFF;
end;

function hCollection.Region: hRegion;
begin
  // 2^8 + 2^12
  Result.v := v shr 12 and $FFF;
end;

function hCollection.Counter: Byte;
begin
  // 2^8 0..255
  Result := (v shr 24) and $FF;
end;

{$EndRegion}

{$Region 'TsgHandleManager.TNode'}

procedure TsgHandleManager.TNode.Init(idx: Integer);
begin
  ptr := nil;
  // next := idx; counter := 1;
  v := idx + (1 shr 12);
end;

function TsgHandleManager.TNode.GetNext: TIndex;
begin
  Result := v and $FFF;
end;

procedure TsgHandleManager.TNode.SetNext(const Value: TIndex);
begin
  v := v or (Ord(Value) and $FFF);
end;

function TsgHandleManager.TNode.GetActive: Boolean;
begin
  Result := False;
  if v and $80000000 <> 0 then
    Result := True;
end;

procedure TsgHandleManager.TNode.SetActive(const Value: Boolean);
begin
  if Value then
    v := v or $80000000
  else
    v := v and not $80000000;
end;

function TsgHandleManager.TNode.GetCounter: Byte;
begin
  Result := (v shr 12) and $FF;
end;

procedure TsgHandleManager.TNode.SetCounter(const Value: Byte);
begin
  v := v or ((Ord(Value) and $FF) shl 12);
end;

function TsgHandleManager.TNode.GetEol: Boolean;
begin
  Result := False;
  if v and $40000000 <> 0 then
    Result := True;
end;

procedure TsgHandleManager.TNode.SetEol(const Value: Boolean);
begin
  if Value then
    v := v or $40000000
  else
    v := v and not $40000000;
end;

{$EndRegion}

{$Region 'TsgHandleManager'}

procedure TsgHandleManager.Init(region: hRegion);
var
  i: Integer;
  n: PNode;
begin
  FUsed := 0;
  FAvail := 0;
  FRegion := region;
  for i := 0 to  MaxNodes - 1 do
  begin
    n := @FNodes[i];
    n.Init(i + 1);
  end;
  n.v := $40000000; // n.Eol := True;
end;

function TsgHandleManager.Add(p: Pointer): hCollection;
var
  idx: Integer;
  n: PNode;
begin
  Assert(FCount < MaxNodes - 1);
  idx := FAvail;
  Assert(idx < MaxNodes);
  n := @FNodes[idx];
  Assert(not n.active and not n.eol);
  FAvail := n.next;
  n.next := 0;
  n.counter := n.counter + 1;
  if n.counter = 0 then
    n.counter := 1;
  n.active := True;
  n.ptr := p;
  Inc(FCount);
  Result := hCollection.From(idx, n.counter, FRegion);
end;

procedure TsgHandleManager.Update(handle: hCollection; p: Pointer);
var
  n: PNode;
begin
  n := @FNodes[handle.Index];
  Assert(n.active);
  Assert(n.counter = handle.counter);
  n.ptr := p;
end;

procedure TsgHandleManager.Remove(handle: hCollection);
var
  idx: Integer;
  n: PNode;
begin
  idx := handle.Index;
  n := @FNodes[idx];
  Assert(n.active);
  Assert(n.counter = handle.counter);
  n.next := FAvail;
  n.active := False;
  FAvail := idx;
  Dec(FCount);
end;

function TsgHandleManager.Get(handle: hCollection): Pointer;
var
  n: PNode;
begin
  n := @FNodes[handle.Index];
  if (n.counter <> handle.counter) or not n.active then exit(nil);
  Result := n.ptr;
end;

{$EndRegion}

end.

