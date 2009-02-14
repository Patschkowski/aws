------------------------------------------------------------------------------
--                              Ada Web Server                              --
--                                                                          --
--                       Copyright (C) 2008, AdaCore                        --
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

with Ada.Streams;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with AWS.Attachments;
with AWS.Client;
with AWS.Containers.Tables;
with AWS.Headers.Set;
with AWS.MIME;
with AWS.Net.Log;
with AWS.Response;
with AWS.Server;
with AWS.Status;
with AWS.Translator;
with AWS.Utils;

with Get_Free_Port;

procedure Attachment_Headers is

   use Ada;
   use Ada.Streams;
   use Ada.Strings.Unbounded;
   use AWS;

   function "-" (S : in Unbounded_String) return String renames To_String;

   ----------
   -- Dump --
   ----------

   procedure Dump
     (Direction : in Net.Log.Data_Direction;
      Socket    : in Net.Socket_Type'Class;
      Data      : in Stream_Element_Array;
      Last      : in Stream_Element_Offset)
   is
      use type Net.Log.Data_Direction;
   begin
      if Direction = Net.Log.Sent then
         Text_IO.Put_Line
           ("********** " & Net.Log.Data_Direction'Image (Direction));
         Text_IO.Put_Line
           (Translator.To_String (Data (Data'First .. Last)));
         Text_IO.New_Line;
      end if;
   end Dump;

   ------------
   -- Upload --
   ------------

   function Upload (Request : in Status.Data) return Response.Data is

      procedure Process_Attachment
        (Attachment : in AWS.Attachments.Element;
         Index      : in Positive;
         Quit       : in out Boolean);
      --  Process each attachment

      ------------------------
      -- Process_Attachment --
      ------------------------

      procedure Process_Attachment
        (Attachment : in AWS.Attachments.Element;
         Index      : in Positive;
         Quit       : in out Boolean)
      is
         Filename     : constant String :=
                          AWS.Attachments.Local_Filename (Attachment);
         Headers      : constant AWS.Headers.List :=
                          AWS.Attachments.Headers (Attachment);
         Header_Names : constant Containers.Tables.VString_Array :=
                          Containers.Tables.Get_Names
                            (Containers.Tables.Table_Type (Headers));
      begin
         Text_IO.Put_Line ("Attachment headers:");
         for Index in Header_Names'Range loop
            Text_IO.Put_Line (-Header_Names (Index));
         end loop;
      end Process_Attachment;

      procedure Process_Attachments is
         new AWS.Attachments.For_Every_Attachment (Process_Attachment);

      Attachments  : constant AWS.Attachments.List :=
                       Status.Attachments (Request);
      Headers      : constant AWS.Headers.List := Status.Header (Request);
      Header_Names : constant Containers.Tables.VString_Array :=
                       Containers.Tables.Get_Names
                         (Containers.Tables.Table_Type (Headers));

   begin
      Text_IO.Put_Line ("Post headers:");

      for Index in Header_Names'Range loop
         Text_IO.Put_Line (-Header_Names (Index));
      end loop;

      Process_Attachments (Attachments);

      return Response.Build (MIME.Text_HTML, "OK");
   end Upload;

   Attachments : AWS.Attachments.List;
   Headers     : AWS.Headers.List;
   Result      : AWS.Response.Data;
   Port        : Positive := 9976;
   Srv         : Server.HTTP;

begin
   Text_IO.Put_Line ("Start...");

   Get_Free_Port (Port);

   Server.Start
     (Srv, "attachment_headers",
      Upload'Unrestricted_Access,
      Upload_Directory => ".",
      Port             => Port);

   AWS.Headers.Set.Add
     (Headers, Name => "X-Message-Seconds", Value => "64");
   AWS.Headers.Set.Add
     (Headers, Name => "Custom-Header", Value => "A Value");
   AWS.Headers.Set.Add
     (Headers, Name => "Content-Custom-Header", Value => "Something else");

   Text_IO.Put_Line ("Insert attachment...");

   AWS.Attachments.Add
     (Attachments => Attachments,
      Filename => "test.py", Headers => Headers);

   Text_IO.Put_Line ("Call Post...");

   --  AWS.Net.Log.Start (Dump'Unrestricted_Access);

   Result := Client.Post
     (URL          => "http://localhost:" & Utils.Image (Port) & "/upload",
      Data         => "ID=1",
      Content_Type => MIME.Application_Form_Data,
      Attachments  => Attachments,
      Headers      => Headers);

   Server.Shutdown (Srv);
end Attachment_Headers;