------------------------------------------------------------------------------
--                              Ada Web Server                              --
--                                                                          --
--                         Copyright (C) 2000-2001                          --
--                               ACT-Europe                                 --
--                                                                          --
--  Authors: Dmitriy Anisimkov - Pascal Obry                                --
--                                                                          --
--  This library is free software; you can redistribute it and/or modify    --
--  it under the terms of the GNU General Public License as published by    --
--  the Free Software Foundation; either version 2 of the License, or (at   --
--  your option) any later version.                                         --
--                                                                          --
--  This library is distributed in the hope that it will be useful, but     --
--  WITHOUT ANY WARRANTY; without even the implied warranty of              --
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU       --
--  General Public License for more details.                                --
--                                                                          --
--  You should have received a copy of the GNU General Public License       --
--  along with this library; if not, write to the Free Software Foundation, --
--  Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.          --
--                                                                          --
--  As a special exception, if other files instantiate generics from this   --
--  unit, or you link this unit with other files to produce an executable,  --
--  this  unit  does not  by itself cause  the resulting executable to be   --
--  covered by the GNU General Public License. This exception does not      --
--  however invalidate any other reasons why the executable file  might be  --
--  covered by the  GNU Public License.                                     --
------------------------------------------------------------------------------
--  $Id$

--  Candidate for regression test of the socket timeout.

with AWS.Net;
with Ada.Streams;
with Ada.Text_IO;
with Ada.Exceptions;

procedure SockTO is
   use AWS;
   use Ada;
   use Streams;

   Port : constant := 8800;

   D1   : constant Duration := 1.0;
   D2   : constant Duration := D1 * 1.5;

   task Client_Side;

   function Data (Length : Stream_Element_Count) return Stream_Element_Array;
   pragma Inline (Data);

   procedure Get
     (Socket : in Net.Socket_Type'Class;
      Length : in Stream_Element_Count);
   --  Read all data length.

   -----------------
   -- Client_Side --
   -----------------

   task body Client_Side is
      Client : Net.Socket_Type'Class := Net.Socket (False);
   begin
      Net.Connect (Client, "localhost", Port);

      for J in 1 .. 5 loop
         Net.Send (Client, Data (1234));
         delay D2;
      end loop;

      Net.Set_Timeout (Client, D1);

      delay D2;

      Get (Client, 100_000);
   exception
      when E : others =>
         Text_IO.Put_Line
           ("Client side " & Exceptions.Exception_Message (E));
   end Client_Side;

   ----------
   -- Data --
   ----------

   function Data
     (Length : Stream_Element_Count)
      return Stream_Element_Array
   is
      Result : Stream_Element_Array (1 .. Length);
   begin
      for J in Result'Range loop
         Result (J)
           := Stream_Element
                (J mod (Stream_Element_Offset (Stream_Element'Last) + 1));
      end loop;

      return Result;
   end Data;

   ---------
   -- Get --
   ---------

   procedure Get
     (Socket : in Net.Socket_Type'Class;
      Length : in Stream_Element_Count)
   is
      Sample : constant Stream_Element_Array := Data (Length);
      Rest   : Stream_Element_Count  := Length;
      Index  : Stream_Element_Offset := Sample'First;
   begin
      loop
         declare
            Buffer : constant Stream_Element_Array
              := Net.Receive (Socket, Rest);
            Next   : constant Stream_Element_Offset := Index + Buffer'Length;
         begin
            if Buffer /= Sample (Index .. Next - 1) then
               Text_IO.Put_Line
                 ("Data error" & Integer'Image (Buffer'Length)
                  & Stream_Element'Image (Buffer (Buffer'First))
                  & Stream_Element'Image (Sample (Sample'First)));
            end if;

            exit when Next > Sample'Last;

            Rest  := Rest - Buffer'Length;
            Index := Next;
         end;
      end loop;

      Text_IO.Put_Line ("Got length" & Stream_Element_Count'Image (Length));
   exception
      when E : others =>
         Text_IO.Put_Line
           ("Got length"
            & Stream_Element_Count'Image (Length - Rest)
            & ' ' & Exceptions.Exception_Message (E));
   end Get;

   Server, Peer : Net.Socket_Type'Class := Net.Socket (False);

begin
   Net.Bind (Server, Port);
   Net.Listen (Server);

   Net.Accept_Socket (Server, Peer);

   Net.Set_Timeout (Peer, D1);

   for J in 1 .. 10 loop
      Get (Peer, 1234);
   end loop;

   Net.Send (Peer, Data (100_000));

   Net.Shutdown (Server);
   Net.Shutdown (Peer);
exception
   when E : others =>
      Text_IO.Put_Line
         ("Server side " & Exceptions.Exception_Message (E));
      Net.Shutdown (Server);
      Net.Shutdown (Peer);
end SockTO;