------------------------------------------------------------------------------
--                              Ada Web Server                              --
--                                                                          --
--                     Copyright (C) 2003-2015, AdaCore                     --
--                                                                          --
--  This library is free software;  you can redistribute it and/or modify   --
--  it under terms of the  GNU General Public License  as published by the  --
--  Free Software  Foundation;  either version 3,  or (at your  option) any --
--  later version. This library is distributed in the hope that it will be  --
--  useful, but WITHOUT ANY WARRANTY;  without even the implied warranty of --
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.                    --
--                                                                          --
--  As a special exception under Section 7 of GPL version 3, you are        --
--  granted additional permissions described in the GCC Runtime Library     --
--  Exception, version 3.1, as published by the Free Software Foundation.   --
--                                                                          --
--  You should have received a copy of the GNU General Public License and   --
--  a copy of the GCC Runtime Library Exception along with this program;    --
--  see the files COPYING3 and COPYING.RUNTIME respectively.  If not, see   --
--  <http://www.gnu.org/licenses/>.                                         --
--                                                                          --
--  As a special exception, if other files instantiate generics from this   --
--  unit, or you link this unit with other files to produce an executable,  --
--  this  unit  does not  by itself cause  the resulting executable to be   --
--  covered by the GNU General Public License. This exception does not      --
--  however invalidate any other reasons why the executable file  might be  --
--  covered by the  GNU Public License.                                     --
------------------------------------------------------------------------------

pragma Ada_2012;

with Ada.Characters.Handling;
with Ada.Containers.Indefinite_Vectors;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Maps;
with Ada.Text_IO;

with DOM.Core.Nodes;

with AWS.Utils;
with SOAP.Utils;
with SOAP.WSDL.Name_Spaces;
with SOAP.WSDL.Schema;
with SOAP.WSDL.Types;
with SOAP.XML;

package body SOAP.WSDL.Parser is

   use Ada;
   use type DOM.Core.Node;

   Verbose_Mode  : Verbose_Level := 0;
   Skip_Error    : Boolean       := False;
   NS_SOAP       : Unbounded_String;
   NS_Num        : Natural := 0;

   type Look_Kind is (Complex_Type, Simple_Type, Element);
   type Look_Context is array (Look_Kind) of Boolean;

   Look_All : constant Look_Context := (others => True);

   package String_List is new Containers.Indefinite_Vectors (Positive, String);

   function Get_Node
     (Parent  : DOM.Core.Node;
      Element : String;
      Name    : String        := "";
      NS      : Boolean       := False) return DOM.Core.Node;
   --  Returns child node named Element having the value Name for attribute
   --  "name" if specified.

   function "+" (Str : String) return Unbounded_String
     renames To_Unbounded_String;

   function "-" (Str : Unbounded_String) return String
     renames To_String;

   procedure Parse_Service
     (O        : in out Object'Class;
      Service  : DOM.Core.Node;
      Document : WSDL.Object);
   --  Parse WSDL service nodes

   procedure Parse_Binding
     (O        : in out Object'Class;
      Binding  : DOM.Core.Node;
      Document : WSDL.Object);
   --  Parse WSDL binding nodes

   procedure Parse_Definitions
     (O           : Object'Class;
      Definitions : DOM.Core.Node;
      Document    : WSDL.Object);
   --  Parse WSDL definition node

   procedure Parse_Operation
     (O         : in out Object'Class;
      Operation : DOM.Core.Node;
      Document  : WSDL.Object);
   --  Parse WSDL operation nodes

   procedure Parse_PortType
     (O         : in out Object'Class;
      Operation : DOM.Core.Node;
      Document  : WSDL.Object);
   --  Parse WSDL PortType nodes

   procedure Parse_Part
     (O        : in out Object'Class;
      Part     : DOM.Core.Node;
      Document : WSDL.Object);
   --  Parse WSDL part nodes

   procedure Parse_Message
     (O        : in out Object'Class;
      Message  : DOM.Core.Node;
      Document : WSDL.Object);
   --  Parse WSDL message nodes

   procedure Parse_Element
     (O        : in out Object'Class;
      Element  : DOM.Core.Node;
      Document : WSDL.Object);
   --  Parse WSDL element nodes

   procedure Add_Parameter
     (O         : in out Object'Class;
      Name      : String;
      Type_Name : String)
     with Inline;
   --  Add parameter Name / P_Type into O using current mode (O.Mode)

   procedure Add_Parameter
     (O     : in out Object'Class;
      Param : Parameters.Parameter)
     with Inline;
   --  Add parameter into O using current mode (O.Mode)

   function Parse_Parameter
     (O        : in out Object'Class;
      N        : DOM.Core.Node;
      Document : WSDL.Object) return Parameters.Parameter;
   --  Returns parameter in node P

   function Parse_Record
     (O        : in out Object'Class;
      R        : DOM.Core.Node;
      Document : WSDL.Object) return Parameters.Parameter;
   --  Returns record in node R

   function Parse_Array
     (O        : in out Object'Class;
      R        : DOM.Core.Node;
      Document : WSDL.Object) return Parameters.Parameter;
   --  Returns array in node R

   function Parse_Set
     (O        : in out Object'Class;
      S        : DOM.Core.Node;
      Document : WSDL.Object) return Parameters.Parameter;
   --  Returns array in node S. A set if used to handle parameters with a
   --  minOccurs or maxOccurs different to 1.

   function Parse_Simple
     (O        : in out Object'Class;
      R        : DOM.Core.Node;
      Document : WSDL.Object) return Parameters.Parameter;
   --  Returns the derived or enumeration type in node N (N must be a
   --  simpleType schema node).

   procedure Parse_Schema
     (O     : in out Object'Class;
      Root  : DOM.Core.Node;
      XPath : String);
   --  Parse a schema node

   function Is_Array
     (O : Object'Class;
      N : DOM.Core.Node) return Boolean;
   --  Returns True if N is an array description node. Set the array element
   --  name into the object.

   function Is_Record
     (O : Object'Class;
      N : DOM.Core.Node) return Boolean;
   --  Returns True if N is a struct description node

   function Get_Target_Name_Space
     (N : DOM.Core.Node) return Name_Space.Object;
   --  Returns the targetNamespace

   procedure Register_Name_Spaces (N : DOM.Core.Node);
   --  Register namespace pointing at node N

   function Get_Namespaces_For (N : DOM.Core.Node) return String_List.Vector;
   --  Get all possible name spaces for the item at the given node. This is the
   --  target namespace and all imported namespace.

   function Look_For_Schema
     (N         : DOM.Core.Node;
      Type_Name : String;
      Document  : WSDL.Object;
      Context   : Look_Context := Look_All) return DOM.Core.Node;
   --  Look for schema starting at

   function Is_Character
     (N         : DOM.Core.Node;
      Type_Name : String;
      Document  : WSDL.Object) return Boolean;
   --  Returns True if Type_Name corresponds to a character type

   procedure Skip_Annotation (N : in out DOM.Core.Node);
   --  Skip annotation node

   function Get_Documentation (N : DOM.Core.Node) return String;
   --  Get text for the documentation node N

   procedure Get_Min_Max (S_Min, S_Max : String; Min, Max : out Natural);
   --  Returns the Min, Max values for the given string

   -----------
   -- Debug --
   -----------

   procedure Trace (Message : String; N : DOM.Core.Node);
   --  Display trace message and info about the node

   ----------------
   -- Accept_RPC --
   ----------------

   procedure Accept_Document (O : in out Object'Class) is
   begin
      O.Accept_Document := True;
   end Accept_Document;

   -------------------
   -- Add_Parameter --
   -------------------

   procedure Add_Parameter
     (O         : in out Object'Class;
      Name      : String;
      Type_Name : String) is
   begin
      if not O.No_Param then
         Parameters.Append
           (O.Params (O.Mode),
            (WSDL.Types.K_Simple, +Name, Null_Unbounded_String,
             Typ  => Types.Create (Utils.No_NS (Type_Name), Name_Space.XSD),
             Min  => 1,
             Max  => 1,
             Next => null));
      end if;
   end Add_Parameter;

   procedure Add_Parameter
     (O     : in out Object'Class;
      Param : Parameters.Parameter) is
   begin
      if not O.No_Param then
         Parameters.Append (O.Params (O.Mode), Param);
      end if;
   end Add_Parameter;

   -----------------------
   -- Continue_On_Error --
   -----------------------

   procedure Continue_On_Error is
   begin
      Skip_Error := True;
   end Continue_On_Error;

   --------------
   -- Encoding --
   --------------

   function Encoding
     (O    : Object'Class;
      Kind : Parameter_Mode) return SOAP.Types.Encoding_Style is
   begin
      case Kind is
         when Input =>
            return O.I_Encoding;
         when Output | Fault =>
            --  ??? fault taken as output
            return O.O_Encoding;
      end case;
   end Encoding;

   -------------
   -- Exclude --
   -------------

   procedure Exclude (O : in out Object; Operation : String) is
      Pos     : Name_Set.Cursor;
      Success : Boolean;
   begin
      O.Exclude.Insert (Operation, Pos, Success);
   end Exclude;

   -----------------------
   -- Get_Documentation --
   -----------------------

   function Get_Documentation (N : DOM.Core.Node) return String is
      Trim_Set : constant Strings.Maps.Character_Set :=
                   Strings.Maps.To_Set (ASCII.LF & ASCII.CR);
      D        : DOM.Core.Node := DOM.Core.Nodes.First_Child (N);
      Doc      : Unbounded_String;
   begin
      while D /= null loop
         if DOM.Core.Nodes.Node_Name (D) = "#text" then
            declare
               V : Unbounded_String := +DOM.Core.Nodes.Node_Value (D);
               P : Natural;
               E : Boolean := True;
            begin
               loop
                  E := True;

                  P := Index (V, "  ");
                  if P /= 0 then
                     Strings.Unbounded.Delete (V, P, P);
                     E := False;
                  end if;

                  P := Index (V, Trim_Set);
                  if P /= 0 then
                     Strings.Unbounded.Delete (V, P, P);
                     E := False;
                  end if;

                  exit when E;
               end loop;

               if Doc /= Null_Unbounded_String then
                  Append (Doc, " ");
               end if;

               --  Then finaly removes leading/trainling white spaces

               Append (Doc, Strings.Unbounded.Trim (V, Side => Strings.Both));
            end;
         end if;

         D := DOM.Core.Nodes.Next_Sibling (D);
      end loop;

      return To_String (Doc);
   end Get_Documentation;

   -----------------
   -- Get_Min_Max --
   -----------------

   procedure Get_Min_Max (S_Min, S_Max : String; Min, Max : out Natural) is
   begin
      if S_Min = "" then
         Min := 1;
      else
         Min := Natural'Value (S_Min);
      end if;

      if S_Max = "" then
         Max := 1;
      elsif Characters.Handling.To_Lower (S_Max) = "unbounded" then
         Max := Natural'Last;
      else
         Max := Positive'Value (S_Max);
      end if;
   end Get_Min_Max;

   ------------------------
   -- Get_Namespaces_For --
   ------------------------

   function Get_Namespaces_For (N : DOM.Core.Node) return String_List.Vector is
      NS : constant Name_Space.Object := Get_Target_Name_Space (N);
      R  : DOM.Core.Node := N;
      V  : String_List.Vector;
   begin
      Look_For_Import : loop
         if DOM.Core.Nodes.Local_Name (R) = "import"
           and then XML.Get_Attr_Value (R, "namespace", True) /= ""
         then
            V.Append (XML.Get_Attr_Value (R, "namespace", True));
         end if;

         if DOM.Core.Nodes.Previous_Sibling (R) = null then
            R := DOM.Core.Nodes.Parent_Node (R);
         else
            R := DOM.Core.Nodes.Previous_Sibling (R);
         end if;

         exit Look_For_Import when R = null;
      end loop Look_For_Import;

      V.Append (Name_Space.Value (NS));

      return V;
   end Get_Namespaces_For;

   --------------
   -- Get_Node --
   --------------

   function Get_Node
     (Parent  : DOM.Core.Node;
      Element : String;
      Name    : String        := "";
      NS      : Boolean       := False) return DOM.Core.Node
   is
      function Get_Node_Int
        (Parent  : DOM.Core.Node;
         Element : String;
         Name    : String) return DOM.Core.Node;
      --  Recursive procedure that does the job

      ------------------
      -- Get_Node_Int --
      ------------------

      function Get_Node_Int
        (Parent  : DOM.Core.Node;
         Element : String;
         Name    : String) return DOM.Core.Node
      is
         N, R : DOM.Core.Node;
         E    : Natural;
      begin
         if Element = "" then
            --  No more element to look for
            if Name = ""
              or else XML.Get_Attr_Value (Parent, "name") = Name
            then
               --  There is no attribute to look for or we are in the right
               --  node, return this node.
               return Parent;
            else
               --  No found otherwise
               return null;
            end if;
         end if;

         E := Strings.Fixed.Index (Element, ".");

         if E = 0 then
            --  No more separator, this is the last element
            E := Element'Last;
         else
            E := E - 1;
         end if;

         --  Iterate through childs, look for element

         N := XML.First_Child (Parent);

         declare
            E_Name : constant String := Element (Element'First .. E);
         begin
            R := null;

            while N /= null loop
               if (not NS and then DOM.Core.Nodes.Local_Name (N) = E_Name)
                 or else (NS and then DOM.Core.Nodes.Node_Name (N) = E_Name)
               then
                  --  We found this element, check next one
                  R := Get_Node_Int
                    (N, Element (E + 2 .. Element'Last), Name);
                  --  Exit now ff we have found the right node, otherwise let's
                  --  try the next sibling.
                  exit when R /= null;
               end if;
               N := XML.Next_Sibling (N);
            end loop;
         end;

         return R;
      end Get_Node_Int;

   begin
      Trace ("(Get_Node) - " & Element & " -> " & Name, Parent);

      return Get_Node_Int (Parent, Element, Name);
   end Get_Node;

   ---------------------------
   -- Get_Target_Name_Space --
   ---------------------------

   function Get_Target_Name_Space
     (N : DOM.Core.Node) return Name_Space.Object
   is

      function Create (Value : String) return Name_Space.Object;

      ------------
      -- Create --
      ------------

      function Create (Value : String) return Name_Space.Object is
      begin
         if WSDL.Name_Spaces.Contains (Value) then
            return Name_Space.Create (WSDL.Name_Spaces.Get (Value), Value);

         else
            NS_Num := NS_Num + 1;
            declare
               Name : constant String := "n" & AWS.Utils.Image (NS_Num);
            begin
               WSDL.Name_Spaces.Register (Value, Name);
               return Name_Space.Create (Name, Value);
            end;
         end if;
      end Create;

      V : constant String := XML.Get_Attr_Value (N, "targetNamespace", True);

   begin
      if V = "" then
         if DOM.Core.Nodes.Parent_Node (N) /= null then
            return Get_Target_Name_Space (DOM.Core.Nodes.Parent_Node (N));

         else
            raise WSDL_Error with "cannot find name space";
         end if;

      else
         return Create (V);
      end if;
   end Get_Target_Name_Space;

   --------------
   -- Is_Array --
   --------------

   function Is_Array
     (O : Object'Class;
      N : DOM.Core.Node) return Boolean
   is
      function Array_Elements return Types.Object;
      --  Returns array's element type encoded in node L

      L : DOM.Core.Node := N;

      --------------------
      -- Array_Elements --
      --------------------

      function Array_Elements return Types.Object is
         Attributes : constant  DOM.Core.Named_Node_Map :=
                        DOM.Core.Nodes.Attributes (L);
      begin
         --  Look for arrayType in Attributes list

         for K in 0 .. DOM.Core.Nodes.Length (Attributes) - 1 loop

            declare
               N : constant DOM.Core.Node :=
                     DOM.Core.Nodes.Item (Attributes, K);
            begin
               if Utils.No_NS (DOM.Core.Nodes.Node_Name (N)) = "arrayType" then
                  --  Found get the value removing []
                  declare
                     Value : constant String :=
                               Utils.No_NS (DOM.Core.Nodes.Node_Value (N));
                     First : Natural;
                     Last  : Natural;
                  begin
                     First := Strings.Fixed.Index (Value, "[");
                     Last  := Strings.Fixed.Index (Value, "]");

                     if First = 0 or else Last = 0 then
                        raise WSDL_Error with "missing [] in arrayType value.";
                     end if;

                     if Last > First + 1 then
                        O.Self.Array_Length
                          := Natural'Value (Value (First + 1 .. Last - 1));
                     else
                        O.Self.Array_Length := 0;
                     end if;

                     return Types.Create
                       (Value (Value'First .. First - 1),
                        Get_Target_Name_Space (Is_Array.N));
                  end;
               end if;
            end;
         end loop;

         raise WSDL_Error with "array element type not found.";
      end Array_Elements;

   begin
      if Utils.No_NS (DOM.Core.Nodes.Node_Name (L)) = "complexType" then
         L := XML.First_Child (L);

         Skip_Annotation (L);

         if L /= null
           and then
             Utils.No_NS (DOM.Core.Nodes.Node_Name (L)) = "complexContent"
         then
            L := XML.First_Child (L);

            if L /= null
              and then
                Utils.No_NS (DOM.Core.Nodes.Node_Name (L)) = "restriction"
            then
               L := XML.First_Child (L);

               if L /= null
                 and then
                   Utils.No_NS (DOM.Core.Nodes.Node_Name (L)) = "attribute"
               then
                  O.Self.Array_Elements := Array_Elements;
                  return True;
               end if;
            end if;
         end if;
      end if;

      return False;
   end Is_Array;

   ------------------
   -- Is_Character --
   ------------------

   function Is_Character
     (N         : DOM.Core.Node;
      Type_Name : String;
      Document  : WSDL.Object) return Boolean
   is

      function Is_Character_Schema (R : DOM.Core.Node) return Boolean;

      -------------------------
      -- Is_Character_Schema --
      -------------------------

      function Is_Character_Schema (R : DOM.Core.Node) return Boolean is

         function Character_Facet
           (Parent : DOM.Core.Node;
            Child  : Boolean := False) return DOM.Core.Node;
         --  Returns the first node corresponding to a character type
         --  definition. It skips annotation tag for example.

         ---------------------
         -- Character_Facet --
         ---------------------

         function Character_Facet
           (Parent : DOM.Core.Node;
            Child  : Boolean := False) return DOM.Core.Node
         is
            N : DOM.Core.Node := Parent;
         begin
            if Child then
               N := XML.First_Child (N);
            else
               N := XML.Next_Sibling (N);
            end if;

            while N /= null
              and then DOM.Core.Nodes.Local_Name (N) /= "length"
              and then DOM.Core.Nodes.Local_Name (N) /= "minLength"
              and then DOM.Core.Nodes.Local_Name (N) /= "maxLength"
            loop
               N := XML.Next_Sibling (N);
            end loop;

            return N;
         end Character_Facet;

         N : DOM.Core.Node := R;

      begin
         Trace ("(Is_Character_Schema)", R);

         if Utils.No_NS (DOM.Core.Nodes.Node_Name (R)) /= "simpleType" then
            return False;
         end if;

         --  Now check that if Name is Character and base is xsd:string
         --  that this is really an Ada Character type. For this the
         --  type must be constrained to a single character.
         --
         --  Either we have the facet <length value="1">
         --  Or <minLength value="1"> and <maxLength value="1">

         --  Get restriction node

         N := XML.First_Child (N);

         declare
            Base : constant String := XML.Get_Attr_Value (N, "base", False);
         begin
            if Base /= "string" then
               --  The base type must be a string
               return False;
            end if;

            N := Character_Facet (N, Child => True);

            if N /= null
              and then DOM.Core.Nodes.Local_Name (N) = "length"
            then
               --  Check length

               if XML.Get_Attr_Value (N, "value", False) /= "1" then
                  --  Must be a single character
                  return False;
               end if;

            elsif N /= null
              and then DOM.Core.Nodes.Local_Name (N) = "minLength"
            then

               if XML.Get_Attr_Value (N, "value", False) /= "1" then
                  --  Must be a single character
                  return False;
               end if;

               N := Character_Facet (N);

               if N = null
                 or else DOM.Core.Nodes.Local_Name (N) /= "maxLength"
                 or else XML.Get_Attr_Value (N, "value", False) /= "1"
               then
                  --  Must be a single character
                  return False;
               end if;

            elsif N /= null
              and then DOM.Core.Nodes.Local_Name (N) = "maxLength"
            then

               if XML.Get_Attr_Value (N, "value", False) /= "1" then
                  --  Must be a single character
                  return False;
               end if;

               N := Character_Facet (N);

               if N = null
                 or else DOM.Core.Nodes.Local_Name (N) /= "minLength"
                 or else XML.Get_Attr_Value (N, "value", False) /= "1"
               then
                  --  Must be a single character
                  return False;
               end if;

            else
               --  Must be a single character
               return False;
            end if;
         end;

         return True;
      end Is_Character_Schema;

      S : constant DOM.Core.Node := Look_For_Schema (N, Type_Name, Document);

   begin
      return S /= null and then Is_Character_Schema (S);
   end Is_Character;

   ---------------
   -- Is_Record --
   ---------------

   function Is_Record
     (O : Object'Class;
      N : DOM.Core.Node) return Boolean
   is
      pragma Unreferenced (O);
      L : DOM.Core.Node := N;
   begin
      if Utils.No_NS (DOM.Core.Nodes.Node_Name (L)) = "element"
        and then XML.First_Child (L) /= null
      then
         --  Handle an element enclosing the complexType
         L := XML.First_Child (L);
      end if;

      if Utils.No_NS (DOM.Core.Nodes.Node_Name (L)) = "complexType" then
         L := XML.First_Child (L);

         Skip_Annotation (L);

         --  Empty complexType

         if L = null then
            return True;

         else
            if Utils.No_NS (DOM.Core.Nodes.Node_Name (L))
              = "complexContent"
            then
               L := XML.First_Child (L);
            end if;

            if L = null then
               raise WSDL_Error with "empty complexContent.";

            elsif Utils.No_NS (DOM.Core.Nodes.Node_Name (L))
              = "extension"
            then
               L := XML.First_Child (L);
            end if;
         end if;

         --  Empty extension

         if L = null then
            return True;
         end if;

         if Utils.No_NS (DOM.Core.Nodes.Node_Name (L)) = "all"
           or else Utils.No_NS (DOM.Core.Nodes.Node_Name (L)) = "sequence"
           or else Utils.No_NS (DOM.Core.Nodes.Node_Name (L)) = "choice"
         then
            L := XML.First_Child (L);

            if L /= null
               and then Utils.No_NS (DOM.Core.Nodes.Node_Name (L)) = "element"
            then
               return True;
            end if;
         end if;
      end if;

      return False;
   end Is_Record;

   ---------------------
   -- Look_For_Schema --
   ---------------------

   function Look_For_Schema
     (N         : DOM.Core.Node;
      Type_Name : String;
      Document  : WSDL.Object;
      Context   : Look_Context := Look_All) return DOM.Core.Node
   is
      pragma Unreferenced (Document);

      T_No_NS : constant String := Utils.No_NS (Type_Name);
      T_NS    : constant String := Utils.NS (Type_Name);
      TNS     : constant Name_Space.Object := Get_Target_Name_Space (N);
      D       : DOM.Core.Node;
      All_NS  : constant String_List.Vector := Get_Namespaces_For (N);
   begin
      Trace ("(Look_For_Schema)", N);

      --  First look for imported schema

      declare
         Key : constant String := (if T_NS = ""
                                   then WSDL.Name_Spaces.Get
                                          (Name_Space.Value (TNS))
                                   else T_NS);
         URL : constant String := (if WSDL.Name_Spaces.Contains (Key)
                                   then WSDL.Name_Spaces.Get (Key)
                                   else "");

         procedure Look_Schema (S : DOM.Core.Node);
         --  Look for element/complexType/simpleType definition in schema

         -----------------
         -- Look_Schema --
         -----------------

         procedure Look_Schema (S : DOM.Core.Node) is
         begin
            D := Get_Node (S, "element", T_No_NS);

            if D = null and then Context (Complex_Type) then
               D := Get_Node (S, "complexType", T_No_NS);
            end if;

            if D = null and then Context (Simple_Type) then
               D := Get_Node (S, "simpleType", T_No_NS);
            end if;
         end Look_Schema;

      begin
         --  We have a name-space prefix, use it to find the corresponding
         --  schema definition.

         if URL /= "" then
            WSDL.Schema.For_All (URL, Look_Schema'Access);
         end if;

         --  Check on the embedded schema

         if D = null then
            for U of All_NS loop
               WSDL.Schema.For_All (U, Look_Schema'Access);
               exit when D /= null;
            end loop;
         end if;

         --  Then check all mixed-schemas

         if D = null then
            WSDL.Schema.For_All
              (Namespace => "", Process => Look_Schema'Access);
         end if;
      end;

      return D;
   end Look_For_Schema;

   -----------
   -- Parse --
   -----------

   procedure Parse
     (O        : in out Object'Class;
      Document : WSDL.Object)
   is
      N     : constant DOM.Core.Node :=
                XML.First_Child (DOM.Core.Node (Document));
      NL    : constant DOM.Core.Node_List := DOM.Core.Nodes.Child_Nodes (N);
      Found : Boolean := False;
   begin
      --  First we want to parse the definitions node to get the namespaces

      Parse_Definitions (O, N, Document);

      --  Record this schema as the targetNamespace schema

      declare
         Embedded_Schema : constant DOM.Core.Node :=
                             Get_Node (DOM.Core.Node (Document),
                                       "definitions.types.schema");
      begin
         if Embedded_Schema /= null then
            Schema.Register
               (Name_Space.Value (Get_Target_Name_Space (Embedded_Schema)),
                Embedded_Schema);
         end if;
      end;

      --  Then we load all external schemas

      Parse_Schema (O, DOM.Core.Node (Document), "definitions.types.schema");

      --  Look for the service node

      for K in 0 .. DOM.Core.Nodes.Length (NL) - 1 loop
         declare
            S : constant DOM.Core.Node := DOM.Core.Nodes.Item (NL, K);
         begin
            if DOM.Core.Nodes.Local_Name (S) = "service" then
               Parse_Service (O, S, Document);
               Found := True;
            end if;
         end;
      end loop;

      if Verbose_Mode > 0 and then not Found then
         Text_IO.New_Line;
         Text_IO.Put_Line ("No service found in this document.");
      end if;
   end Parse;

   -----------------
   -- Parse_Array --
   -----------------

   function Parse_Array
     (O        : in out Object'Class;
      R        : DOM.Core.Node;
      Document : WSDL.Object) return Parameters.Parameter
   is
      P : Parameters.Parameter (Types.K_Array);
      D : Types.Definition (Types.K_Array);
   begin
      Trace ("(Parse_Array)", R);

      pragma Assert
        (R /= null
         and then Utils.No_NS (DOM.Core.Nodes.Node_Name (R)) = "complexType");

      declare
         Name : constant String := XML.Get_Attr_Value (R, "name", False);
      begin
         --  Set array name, R is a complexType node

         P.Name      := O.Current_Name;
         P.Typ       := Types.Create (Name, Get_Target_Name_Space (R));
         P.Length    := O.Array_Length;

         D.Ref       := Types.Create (Name, Types.NS (P.Typ));
         D.E_Type    := O.Array_Elements;

         Types.Register (D);

         --  Get documentation if any

         if Utils.No_NS (DOM.Core.Nodes.Node_Name (XML.First_Child (R)))
           = "annotation"
         then
            Append
              (P.Doc,
               Get_Documentation (XML.First_Child (XML.First_Child (R))));
         end if;

         if not WSDL.Is_Standard (WSDL.Types.Name (O.Array_Elements)) then
            --  This is not a standard type, parse it
            declare
               N : DOM.Core.Node :=
                     Look_For_Schema (R, WSDL.Types.Name (O.Array_Elements),
                                      Document,
                                      Look_Context'(Complex_Type => True,
                                                    others => False));
            begin
               if N = null then
                  N := Look_For_Schema (R, WSDL.Types.Name (O.Array_Elements),
                                        Document,
                                        Look_Context'(Simple_Type => True,
                                                      others      => False));
                  Parameters.Append (P.P, Parse_Simple (O, N, Document));

               else
                  Parameters.Append (P.P, Parse_Record (O, N, Document));
               end if;
            end;
         end if;

         return P;
      end;
   end Parse_Array;

   -------------------
   -- Parse_Binding --
   -------------------

   procedure Parse_Binding
     (O        : in out Object'Class;
      Binding  : DOM.Core.Node;
      Document : WSDL.Object)
   is
      N : DOM.Core.Node;
   begin
      Trace ("(Parse_Binding)", Binding);

      N := Get_Node (Binding, Utils.With_NS (-NS_SOAP, "binding"), NS => True);

      if N = null then
         raise WSDL_Error with "Binding style/transport definition not found.";
      end if;

      --  Check for style (only Document is supported)

      if  XML.Get_Attr_Value (N, "style") = "document" then
         if O.Accept_Document then
            --  We accept document style binding as RPC
            O.Style := Message.RPC;
         else
            O.Style := Message.Document;
         end if;
      end if;

      --  Check for transport (only HTTP is supported)

      declare
         T : constant String := XML.Get_Attr_Value (N, "transport");
      begin
         if T (T'Last - 4 .. T'Last) /= "/http" then
            raise WSDL_Error with "Only HTTP transport supported.";
         end if;
      end;

      --  Read all operations

      declare
         NL : constant DOM.Core.Node_List :=
                DOM.Core.Nodes.Child_Nodes (Binding);
      begin
         for K in 0 .. DOM.Core.Nodes.Length (NL) - 1 loop
            declare
               S : constant DOM.Core.Node := DOM.Core.Nodes.Item (NL, K);
            begin
               if Utils.No_NS (DOM.Core.Nodes.Node_Name (S)) = "operation"
                 and then not O.Exclude.Contains
                   (XML.Get_Attr_Value (S, "name"))
               then
                  begin
                     Parse_Operation
                       (O, DOM.Core.Nodes.Item (NL, K), Document);
                  exception
                     when E : WSDL_Error =>
                        if Skip_Error then
                           Text_IO.Put_Line
                             ("     "
                                & XML.Get_Attr_Value (S, "name")
                                & " skipped : "
                                & Exceptions.Exception_Message (E));
                        else
                           raise WSDL_Error
                             with "(" & XML.Get_Attr_Value (S, "name")
                                & ") " & Exceptions.Exception_Message (E);
                        end if;
                  end;
               end if;
            end;
         end loop;
      end;
   end Parse_Binding;

   -----------------------
   -- Parse_Definitions --
   -----------------------

   procedure Parse_Definitions
     (O           : Object'Class;
      Definitions : DOM.Core.Node;
      Document    : WSDL.Object)
   is
      pragma Unreferenced (O, Document);

      Atts : constant DOM.Core.Named_Node_Map :=
               DOM.Core.Nodes.Attributes (Definitions);
   begin
      Trace ("(Parse_Definitions)", Definitions);

      for K in 0 .. DOM.Core.Nodes.Length (Atts) - 1 loop
         declare
            N : constant DOM.Core.Node := DOM.Core.Nodes.Item (Atts, K);
         begin
            if DOM.Core.Nodes.Node_Value (N) = Name_Space.SOAP_URL then
               NS_SOAP := +DOM.Core.Nodes.Local_Name (N);
            end if;
         end;
      end loop;

      Register_Name_Spaces (Definitions);
   end Parse_Definitions;

   -------------------
   -- Parse_Element --
   -------------------

   procedure Parse_Element
     (O        : in out Object'Class;
      Element  : DOM.Core.Node;
      Document : WSDL.Object)
   is
      N       : DOM.Core.Node := Element;
      CT_Node : DOM.Core.Node;
   begin
      Trace ("(Parse_Element)", Element);

      while N /= null
        and then DOM.Core.Nodes.Local_Name (N) /= "complexType"
        and then DOM.Core.Nodes.Local_Name (N) /= "simpleType"
        and then DOM.Core.Nodes.Local_Name (N) /= "element"
      loop
         N := XML.First_Child (N);
      end loop;

      if N = null then
         raise WSDL_Error with "No element found in schema.";
      else
         CT_Node := N;
      end if;

      if DOM.Core.Nodes.Local_Name (N) = "simpleType" then
         Add_Parameter (O, Parse_Simple (O, CT_Node, Document));

      elsif DOM.Core.Nodes.Local_Name (N) = "element"
        and then XML.First_Child (N) = null
      then
         Add_Parameter (O, Parse_Parameter (O, N, Document));

      else
         --  This is a complexType, continue analyse

         declare
            Parent : constant DOM.Core.Node := N;
            ET     : constant String :=
                       XML.Get_Attr_Value (N, "type", NS => True);
         begin
            if N /= null
              and then DOM.Core.Nodes.Local_Name (N) = "element"
            then
               if ET = "" then
                  --  Move to complexType node
                  N := XML.First_Child (N);

               else
                  --  Get the corresponding type definition

                  N := Look_For_Schema
                    (N, ET, Document,
                     Look_Context'(Complex_Type => True, others => False));
               end if;
            end if;

            --  Enter complexType node

            N := XML.First_Child (N);

            if N = null then
               if XML.Get_Attr_Value (Parent, "abstract") = "true" then
                  raise WSDL_Error with "abstract complexType not suported.";
               end if;
            end if;
         end;

         if Is_Record (O, CT_Node) then
            --  This is a record or composite type

            Add_Parameter (O, Parse_Record (O, CT_Node, Document));

         elsif Is_Array (O, CT_Node) then

            Add_Parameter (O, Parse_Array (O, CT_Node, Document));

         else
            declare
               NL : constant DOM.Core.Node_List :=
                      DOM.Core.Nodes.Child_Nodes (N);
            begin
               for K in 0 .. DOM.Core.Nodes.Length (NL) - 1 loop
                  declare
                     N : constant DOM.Core.Node := DOM.Core.Nodes.Item (NL, K);
                  begin
                     if DOM.Core.Nodes.Node_Name (N) /= "#text" then
                        Add_Parameter (O, Parse_Parameter (O, N, Document));
                     end if;
                  end;
               end loop;
            end;
         end if;
      end if;
   end Parse_Element;

   -------------------
   -- Parse_Message --
   -------------------

   procedure Parse_Message
     (O        : in out Object'Class;
      Message  : DOM.Core.Node;
      Document : WSDL.Object)
   is
      N : DOM.Core.Node := Message;
   begin
      Trace ("(Parse_Message)", Message);

      N := XML.First_Child (N);

      while N /= null loop
         Parse_Part (O, N, Document);
         N := XML.Next_Sibling (N);
      end loop;
   end Parse_Message;

   ---------------------
   -- Parse_Operation --
   ---------------------

   procedure Parse_Operation
     (O         : in out Object'Class;
      Operation : DOM.Core.Node;
      Document  : WSDL.Object)
   is
      N : DOM.Core.Node;
   begin
      Trace ("(Parse_Operation)", Operation);

      O.Proc := +XML.Get_Attr_Value (Operation, "name");

      N := Get_Node
        (Operation, Utils.With_NS (-NS_SOAP, "operation"), NS => True);

      if N = null then
         raise WSDL_Error with "soap:operation not found.";
      end if;

      if DOM.Core.Nodes.Get_Named_Item
        (DOM.Core.Nodes.Attributes (N), "soapAction") = null
      then
         O.SOAPAction := +No_SOAPAction;
      else
         O.SOAPAction := +XML.Get_Attr_Value (N, "soapAction");
      end if;

      N := XML.Next_Sibling (N);

      --  Check that input/output is literal

      Parse_Encoding : declare
         use type Message.Binding_Style;
         use type SOAP.Types.Encoding_Style;

         F : DOM.Core.Node := N;
         B : DOM.Core.Node;
      begin
         while F /= null loop
            declare
               N_Name : constant String :=
                          Utils.No_NS (DOM.Core.Nodes.Node_Name (F));
               E      : SOAP.Types.Encoding_Style;
            begin
               if N_Name in "input" | "output" then
                  B := XML.First_Child (F);

                  declare
                     U : constant String :=
                           Characters.Handling.To_Lower
                             (XML.Get_Attr_Value (B, "use"));
                  begin
                     if U = "literal" then
                        E := SOAP.Types.Literal;
                     elsif U = "encoded" then
                        E := SOAP.Types.Encoded;
                     else
                        raise WSDL_Error with "Unknown encoding type " & U;
                     end if;

                     if N_Name = "input" then
                        O.I_Encoding := E;
                     else
                        O.O_Encoding := E;
                     end if;
                  end;
               end if;
            end;
            F := XML.Next_Sibling (F);
         end loop;

         --  Check for consistency, not that no toolset support
         --  Document/Encoded, so we reject this conbination.

         if (O.I_Encoding = SOAP.Types.Encoded
             or else O.O_Encoding = SOAP.Types.Encoded)
           and then O.Style = Message.Document
         then
            raise WSDL_Error with "document/encoded is not supported";
         end if;
      end Parse_Encoding;

      N := XML.First_Child (N);

      declare
         NS_Value : constant String := XML.Get_Attr_Value (N, "namespace");
         NS_Name  : constant String :=
                      (if WSDL.Name_Spaces.Contains (NS_Value)
                       then WSDL.Name_Spaces.Get (NS_Value)
                       else "");
      begin
         if NS_Value /= "" then
            if NS_Name = "" then
               raise WSDL_Error
                 with "Missing definition for namespace " & NS_Value;
            else
               O.Namespace := Name_Space.Create (NS_Name, NS_Value);
            end if;
         end if;
      end;

      N := Get_Node
        (XML.First_Child (DOM.Core.Node (Document)),
         "portType.operation", -O.Proc);

      if N = null then
         raise WSDL_Error
           with "portType.operation for " & (-O.Proc) & " not found.";
      end if;

      Parse_PortType (O, N, Document);
   end Parse_Operation;

   ---------------------
   -- Parse_Parameter --
   ---------------------

   function Parse_Parameter
     (O        : in out Object'Class;
      N        : DOM.Core.Node;
      Document : WSDL.Object) return Parameters.Parameter
   is
      P_Type : constant String := XML.Get_Attr_Value (N, "type", True);
      S_Min  : constant String := XML.Get_Attr_Value (N, "minOccurs", True);
      S_Max  : constant String := XML.Get_Attr_Value (N, "maxOccurs", True);
      Min    : Natural;
      Max    : Positive;
      Doc    : Unbounded_String;
      D      : DOM.Core.Node := N;
   begin
      Trace ("(Parse_Parameter)", N);

      Get_Min_Max (S_Min, S_Max, Min, Max);

      D := XML.First_Child (N);

      if D /= null
        and then Utils.No_NS (DOM.Core.Nodes.Node_Name (D)) = "annotation"
      then
         Append (Doc, Get_Documentation (XML.First_Child (D)));
      end if;

      if (WSDL.Is_Standard (P_Type) and then To_Type (P_Type) /= P_Character)
        or else Is_Character (N, P_Type, Document)
      then
         if Min = 1 and then Max = 1 then
            return
              (Types.K_Simple, +XML.Get_Attr_Value (N, "name"), Doc,
               Typ  => Types.Create (Utils.No_NS (P_Type), Name_Space.XSD),
               Min  => Min,
               Max  => Max,
               Next => null);
         else
            return Parse_Set (O, N, Document);
         end if;

      elsif P_Type = "anyType" then
         raise WSDL_Error with "Type anyType is not supported.";

      else
         if O.Enclosing_Types.Contains (Utils.No_NS (P_Type)) then
            raise WSDL_Error with
              "Recursive WSDL definition " & P_Type & " is not supported.";
         end if;

         declare
            R : DOM.Core.Node;
         begin
            R := Look_For_Schema
              (N, P_Type, Document,
               Look_Context'(Complex_Type => True,
                             others       => False));

            if R = null then
               --  Now check for a simpleType
               R := Look_For_Schema
                 (N, P_Type, Document,
                  Look_Context'(Simple_Type => True,
                                others      => False));

               if R = null then
                  raise WSDL_Error with
                    "types.schema definition for " & P_Type & " not found.";

               else
                  O.Self.Current_Name := +XML.Get_Attr_Value (N, "name");

                  declare
                     P : Parameters.Parameter := Parse_Simple (O, R, Document);
                  begin
                     P.Min := Min;
                     P.Max := Max;
                     return P;
                  end;
               end if;
            end if;

            if Is_Array (O, R) then
               declare
                  P : Parameters.Parameter := Parse_Array (O, R, Document);
               begin
                  P.Name := +XML.Get_Attr_Value (N, "name");
                  P.Min := Min;
                  P.Max := Max;
                  return P;
               end;

            else
               O.Self.Current_Name := +XML.Get_Attr_Value (N, "name");

               if Min = 1 and then Max = 1 then
                  declare
                     P : Parameters.Parameter := Parse_Record (O, R, Document);
                  begin
                     P.Min := Min;
                     P.Max := Max;
                     return P;
                  end;

               else
                  return Parse_Set (O, N, Document);
               end if;
            end if;
         end;
      end if;
   end Parse_Parameter;

   ----------------
   -- Parse_Part --
   ----------------

   procedure Parse_Part
     (O        : in out Object'Class;
      Part     : DOM.Core.Node;
      Document : WSDL.Object)
   is
      N  : DOM.Core.Node;
      ET : Unbounded_String;
   begin
      Trace ("(Parse_Part)", Part);

      ET := +XML.Get_Attr_Value (Part, "element");

      if ET = Null_Unbounded_String then
         ET := +XML.Get_Attr_Value (Part, "type");
      end if;

      if ET = Null_Unbounded_String then
         raise WSDL_Error
           with "No type or element attribute found for part element.";
      end if;

      O.Current_Name := +XML.Get_Attr_Value (Part, "name");

      declare
         T : constant String := -ET;
      begin
         if (WSDL.Is_Standard (T) and then To_Type (T) /= P_Character)
           or else Is_Character (Part, T, Document)
         then
            Add_Parameter (O, -O.Current_Name, T);

         elsif T = SOAP.Types.XML_Any_Type then
            raise WSDL_Error with "Type anyType is not supported.";

         else
            N := Look_For_Schema (Part, T, Document);

            if N = null then
               raise WSDL_Error with "Definition for " & T & " not found.";
            end if;

            Parse_Element (O, N, Document);
         end if;
      end;
   end Parse_Part;

   --------------------
   -- Parse_PortType --
   --------------------

   procedure Parse_PortType
     (O         : in out Object'Class;
      Operation : DOM.Core.Node;
      Document  : WSDL.Object)
   is
      procedure Get_Element (M : DOM.Core.Node);
      --  Returns the element node which contains parameters for node M

      -----------------
      -- Get_Element --
      -----------------

      procedure Get_Element (M : DOM.Core.Node) is
         N       : DOM.Core.Node;
         Message : Unbounded_String;
      begin
         Message := +XML.Get_Attr_Value (M, "message", False);

         N := Get_Node
           (XML.First_Child (DOM.Core.Node (Document)),
            "message", -Message);

         if N = null then
            --  In this case the message reference the schema element

            N := Look_For_Schema
              (N, -Message, Document,
               Look_Context'(Element => True, others => False));

            if N = null then
               raise WSDL_Error
                 with "types.schema.element for " & (-Message) & " not found.";
            end if;

            Parse_Element (O, N, Document);

         else
            Parse_Message (O, N, Document);
         end if;
      end Get_Element;

      N : DOM.Core.Node;

   begin
      Trace ("(Parse_PortType)", Operation);

      --  Check for documentation

      N := Get_Node (Operation, "documentation");

      if N /= null then
         O.Documentation := +Get_Documentation (N);
      end if;

      --  Input parameters

      N := Get_Node (Operation, "input");

      if N /= null then
         O.Mode := Input;
         Get_Element (N);
      end if;

      --  Output parameters

      N := Get_Node (Operation, "output");

      if N /= null then
         O.Mode := Output;
         Get_Element (N);
      end if;

      --  Fault parameters

      N := Get_Node (Operation, "fault");

      if N /= null then
         O.Mode := Fault;
         Get_Element (N);
      end if;

      if Verbose_Mode > 0 then
         Text_IO.New_Line;
         Text_IO.Put_Line
           ("Procedure " & (-O.Proc) & " SOAPAction:" & (-O.SOAPAction));
         Text_IO.Put_Line ("   Input");
         Parameters.Output (O.Params (Input));

         Text_IO.Put_Line ("   Output");
         Parameters.Output (O.Params (Output));
      end if;

      New_Procedure
        (O, -O.Proc, -O.Documentation, -O.SOAPAction, O.Namespace,
         O.Params (Input), O.Params (Output), O.Params (Fault));

      Parameters.Release (O.Params (Input));
      Parameters.Release (O.Params (Output));
      Parameters.Release (O.Params (Fault));
   end Parse_PortType;

   ------------------
   -- Parse_Record --
   ------------------

   function Parse_Record
     (O        : in out Object'Class;
      R        : DOM.Core.Node;
      Document : WSDL.Object) return Parameters.Parameter
   is
      P : Parameters.Parameter (Types.K_Record);
      D : Types.Definition (Types.K_Record);
      N : DOM.Core.Node;
   begin
      Trace ("(Parse_Record)", R);

      pragma Assert
        (R /= null
         and then
           (Utils.No_NS (DOM.Core.Nodes.Node_Name (R)) = "complexType"
            or else Utils.No_NS (DOM.Core.Nodes.Node_Name (R)) = "element"));

      if XML.Get_Attr_Value (R, "abstract", False) = "true" then
         raise WSDL_Error with "abstract record not supported";
      end if;

      declare
         Name : constant String := XML.Get_Attr_Value (R, "name", False);
      begin
         --  Set record name, R is a complexType or element node

         P.Name      := O.Current_Name;
         P.Typ       := Types.Create (Name, Get_Target_Name_Space (R));

         D.Ref       := Types.Create (Name, Types.NS (P.Typ));
         D.Is_Choice := False;

         O.Self.Enclosing_Types.Include (Name);

         if Utils.No_NS (DOM.Core.Nodes.Node_Name (R)) = "element" then
            --  Skip enclosing element
            N := XML.First_Child (R);
         else
            N := R;
         end if;

         --  Enter complexType element

         if N /= null then
            N := XML.First_Child (N);

            if N /= null then
               if Utils.No_NS (DOM.Core.Nodes.Node_Name (N)) = "choice"  then
                  D.Is_Choice := True;
                  N := XML.First_Child (N);

               elsif Utils.No_NS (DOM.Core.Nodes.Node_Name (N))
                       = "annotation"
               then
                  Append (P.Doc, Get_Documentation (XML.First_Child (N)));
                  N := XML.Next_Sibling (N);
               end if;
            end if;
         end if;

         Types.Register (D);

         --  Check for empty complexType

         if N /= null then
            --  Get first element, if we have a complexContent, parse

            if Utils.No_NS (DOM.Core.Nodes.Node_Name (N))
              = "complexContent"
            then
               N := XML.First_Child (N);

               --  We have an extension, we need to inline the element
               --  definition here.

               if N /= null
                 and then  Utils.No_NS (DOM.Core.Nodes.Node_Name (N))
                   = "extension"
               then
                  declare
                     Base : constant String :=
                              XML.Get_Attr_Value (N, "base", True);
                     CT   : DOM.Core.Node;
                  begin
                     --  Get type whose name is Base

                     CT := Look_For_Schema
                       (N, Base, Document,
                        Look_Context'(Complex_Type => True, others => False));

                     --  Move to the sequence

                     CT := XML.First_Child (CT);

                     --  Get all elements

                     declare
                        NL : constant DOM.Core.Node_List :=
                               DOM.Core.Nodes.Child_Nodes (CT);
                     begin
                        for K in 0 .. DOM.Core.Nodes.Length (NL) - 1 loop
                           declare
                              N : constant DOM.Core.Node :=
                                    DOM.Core.Nodes.Item (NL, K);
                           begin
                              if DOM.Core.Nodes.Node_Name (N)
                                /= "#text"
                              then
                                 Parameters.Append
                                   (P.P, Parse_Parameter (O, N, Document));
                              end if;
                           end;
                        end loop;
                     end;
                  end;

                  --  Move past extension node

                  N := XML.First_Child (N);
               end if;
            end if;

            --  Got to the first element node

            while N /= null
              and then
                Utils.No_NS (DOM.Core.Nodes.Node_Name (N)) /= "element"
            loop
               N := XML.First_Child (N);
            end loop;

            while N /= null loop
               --  Check for annotation

               if Utils.No_NS (DOM.Core.Nodes.Node_Name (N))
                 = "annotation"
               then
                  Append (P.Doc, Get_Documentation (XML.First_Child (N)));
               else
                  Parameters.Append (P.P, Parse_Parameter (O, N, Document));
               end if;

               N := XML.Next_Sibling (N);
            end loop;
         end if;

         O.Enclosing_Types.Exclude (Name);

         return P;
      end;
   end Parse_Record;

   ------------------
   -- Parse_Schema --
   ------------------

   procedure Parse_Schema
     (O     : in out Object'Class;
      Root  : DOM.Core.Node;
      XPath : String)
   is
      N : constant DOM.Core.Node := Get_Node (Root, XPath);
   begin
      if N /= null then
         declare
            NL : constant DOM.Core.Node_List :=
                   DOM.Core.Nodes.Child_Nodes (N);
         begin
            for K in 0 .. DOM.Core.Nodes.Length (NL) - 1 loop
               declare
                  S : constant DOM.Core.Node := DOM.Core.Nodes.Item (NL, K);
                  L : constant String :=
                        XML.Get_Attr_Value (S, "schemaLocation");
               begin
                  if DOM.Core.Nodes.Local_Name (S) = "import"
                    and then L /= ""
                    and then (L'Length < 7
                              or else L (L'First .. L'First + 6) /= "http://")
                  then
                     --  Register the root node of the schema under the
                     --  corresponding namespace.

                     declare
                        N : constant DOM.Core.Node :=
                              DOM.Core.Node
                                (Load
                                   (XML.Get_Attr_Value (S, "schemaLocation")));
                     begin
                        Trace ("(Parse_Schema) "
                               & XML.Get_Attr_Value (S, "namespace"),
                               XML.First_Child (N));

                        Schema.Register
                          (XML.Get_Attr_Value (S, "namespace"),
                           XML.First_Child (N));

                        Register_Name_Spaces (N);

                        --  Check recursively for imported schema

                        Parse_Schema (O, N, "schema");
                     end;
                  end if;
               end;
            end loop;
         end;

         --  If this schema has no targetNamespace then it is a schema
         --  containing definition for different name-space. Record it as
         --  a mixed name-space.

         if XML.Get_Attr_Value (N, "targetNamespace") = "" then
            Schema.Register ("", N);
         end if;
      end if;
   end Parse_Schema;

   -------------------
   -- Parse_Service --
   -------------------

   procedure Parse_Service
     (O        : in out Object'Class;
      Service  : DOM.Core.Node;
      Document : WSDL.Object)
   is
      Port, N            : DOM.Core.Node;
      Name               : Unbounded_String;
      Root_Documentation : Unbounded_String;
      Documentation      : Unbounded_String;
      Location           : Unbounded_String;
      Binding            : Unbounded_String;
   begin
      Trace ("(Parse_Service)", Service);

      Name := +XML.Get_Attr_Value (Service, "name");

      N := Get_Node (Service, "documentation");

      if N /= null then
         Root_Documentation := +Get_Documentation (N);
      end if;

      N := Get_Node
        (XML.First_Child (DOM.Core.Node (Document)),
         "portType.documentation");

      if N /= null then
         Append (Documentation, Get_Documentation (N));
      end if;

      Port := Get_Node (Service, "port");

      if Port = null then
         raise WSDL_Error with "port definition not found";
      end if;

      N := Get_Node (Port, Utils.With_NS (-NS_SOAP, "address"), NS => True);

      if N /= null then
         Location := +XML.Get_Attr_Value (N, "location");
      end if;

      Start_Service (O, -Name, -Root_Documentation, -Documentation, -Location);

      --  Look for the right binding

      Binding := +XML.Get_Attr_Value (Port, "binding", False);

      N := Get_Node
        (XML.First_Child (DOM.Core.Node (Document)), "binding", -Binding);

      if N = null then
         raise WSDL_Error
           with "binding for " & (-Binding) & " not found.";
      end if;

      Parse_Binding (O, N, Document);

      End_Service (O, -Name);
   end Parse_Service;

   ---------------
   -- Parse_Set --
   ---------------

   function Parse_Set
     (O        : in out Object'Class;
      S        : DOM.Core.Node;
      Document : WSDL.Object) return Parameters.Parameter
   is
      P : Parameters.Parameter (Types.K_Array);
      D : Types.Definition (Types.K_Array);
   begin
      Trace ("(Parse_Set)", S);

      pragma Assert
        (S /= null
         and then Utils.No_NS (DOM.Core.Nodes.Node_Name (S)) = "element");

      declare
         Name  : constant String := XML.Get_Attr_Value (S, "name", False);
         Typ   : constant String := XML.Get_Attr_Value (S, "type", False);
         S_Min : constant String := XML.Get_Attr_Value (S, "minOccurs", False);
         S_Max : constant String := XML.Get_Attr_Value (S, "maxOccurs", False);
      begin
         P.Name := +Name;
         P.Typ  := Types.Create (Typ & "_Set", Get_Target_Name_Space (S));

         Get_Min_Max (S_Min, S_Max, P.Min, P.Max);

         if P.Min = P.Max then
            P.Length := P.Min;
         else
            P.Length := 0;
         end if;

         D.Ref       := Types.Create (Typ & "_Set", Types.NS (P.Typ));
         D.E_Type    := Types.Create (Typ, Get_Target_Name_Space (S));

         Types.Register (D);

         if not WSDL.Is_Standard (Typ) then
            --  This is not a standard type, parse it
            declare
               N : constant DOM.Core.Node :=
                     Look_For_Schema (S, Typ, Document,
                                      Look_Context'(Complex_Type => True,
                                                    others => False));
            begin
               --  ??? Right now pretend that it is a record, there is
               --  certainly some cases not covered here.
               Parameters.Append (P.P, Parse_Record (O, N, Document));
            end;
         end if;

         return P;
      end;
   end Parse_Set;

   ------------------
   -- Parse_Simple --
   ------------------

   function Parse_Simple
     (O        : in out Object'Class;
      R        : DOM.Core.Node;
      Document : WSDL.Object) return Parameters.Parameter
   is

      function Build_Derived
        (Name, Base  : String;
         Constraints : WSDL.Types.Constraints_Def;
         N           : DOM.Core.Node) return Parameters.Parameter;
      --  Returns the derived (from standard Ada type) type definition

      function Build_Enumeration
        (Name, Base : String;
         E          : DOM.Core.Node) return Parameters.Parameter;
      --  Returns the enumeration type definition

      -------------------
      -- Build_Derived --
      -------------------

      function Build_Derived
        (Name, Base  : String;
         Constraints : WSDL.Types.Constraints_Def;
         N           : DOM.Core.Node) return Parameters.Parameter
      is
         BNS : constant String := Utils.NS (Base);
         P   : Parameters.Parameter (Types.K_Derived);
         D   : Types.Definition (Types.K_Derived);
      begin
         P.Name      := O.Current_Name;
         P.Typ       := Types.Create
           (Name, Get_Target_Name_Space (DOM.Core.Nodes.Parent_Node (N)));
         D.Constraints := Constraints;

         D.Ref    := Types.Create (Name, Types.NS (P.Typ));
         D.Parent := Types.Create
           (Utils.No_NS (Base),
            (if BNS = ""
             then Types.NS (P.Typ)
             else Name_Space.Create (BNS, WSDL.Name_Spaces.Get (BNS))));

         Types.Register (D);

         return P;
      end Build_Derived;

      -----------------------
      -- Build_Enumeration --
      -----------------------

      function Build_Enumeration
        (Name, Base : String;
         E          : DOM.Core.Node) return Parameters.Parameter
      is
         pragma Unreferenced (Base);

         use type Types.E_Node_Access;

         P : Parameters.Parameter (Types.K_Enumeration);
         D : Types.Definition (Types.K_Enumeration);
         N : DOM.Core.Node := E;
         R : Types.E_Node_Access;
      begin
         --  ??PO R not needed above

         P.Name      := O.Current_Name;
         P.Typ       := Types.Create
           (Name, Get_Target_Name_Space (DOM.Core.Nodes.Parent_Node (E)));
         D.Ref := Types.Create (Name, Types.NS (P.Typ));

         while N /= null
           and then Utils.No_NS (DOM.Core.Nodes.Node_Name (E)) = "enumeration"
         loop
            declare
               Value    : constant String :=
                            XML.Get_Attr_Value (N, "value", False);
               New_Node : constant Types.E_Node_Access :=
                            new Types.E_Node'
                              (To_Unbounded_String (Value), null);
            begin
               if R = null then
                  D.E_Def := New_Node;
               else
                  R.Next := New_Node;
               end if;

               R := New_Node;
            end;

            N := XML.Next_Sibling (N);
         end loop;

         Types.Register (D);

         return P;
      end Build_Enumeration;

      N, E : DOM.Core.Node;
      C    : WSDL.Types.Constraints_Def;

      Name : Unbounded_String;
      Base : Unbounded_String;

   begin
      Trace ("(Parse_Simple)", R);

      pragma Assert
        (R /= null
         and then Utils.No_NS (DOM.Core.Nodes.Node_Name (R)) = "simpleType");

      Name := +XML.Get_Attr_Value (R, "name", False);

      --  Enter simpleType restriction

      N := XML.First_Child (R);

      Skip_Annotation (N);

      Base := +XML.Get_Attr_Value (N, "base", True);

      --  Check if this is an enumeration

      E := XML.First_Child (N);

      if E /= null
        and then Utils.No_NS (DOM.Core.Nodes.Node_Name (E)) = "enumeration"
      then
         return Build_Enumeration (-Name, -Base, E);

      else
         --  Check restrictions for this type

         declare
            R : DOM.Core.Node := XML.First_Child (N);
         begin
            while R /= null loop
               declare
                  Name  : constant String :=
                            Utils.No_NS (DOM.Core.Nodes.Node_Name (R));
                  Value : constant String :=
                            XML.Get_Attr_Value (R, "value", True);
               begin
                  if Name = "minInclusive" then
                     if C.Min_Exclusive /= Null_Unbounded_String then
                        raise WSDL_Error
                          with "Cannot specify minInclusive and minExclusive.";
                     end if;

                     C.Min_Inclusive := +Value;

                  elsif Name = "minExclusive" then
                     if C.Min_Inclusive /= Null_Unbounded_String then
                        raise WSDL_Error
                          with "Cannot specify minInclusive and minExclusive.";
                     end if;

                     C.Min_Exclusive := +Value;

                  elsif Name = "maxInclusive" then
                     if C.Max_Exclusive /= Null_Unbounded_String then
                        raise WSDL_Error
                          with "Cannot specify maxInclusive and maxExclusive.";
                     end if;

                     C.Max_Inclusive := +Value;

                  elsif Name = "maxExclusive" then
                     if C.Max_Inclusive /= Null_Unbounded_String then
                        raise WSDL_Error
                          with "Cannot specify maxInclusive and maxExclusive.";
                     end if;

                     C.Max_Exclusive := +Value;

                  elsif Name = "pattern" then
                     C.Pattern := +Value;

                  elsif Name = "length" then
                     C.Length := Natural'Value (Value);

                  elsif Name = "minLength" then
                     C.Min_Length := Natural'Value (Value);

                  elsif Name = "maxLength" then
                     C.Max_Length := Natural'Value (Value);
                  end if;
               end;

               R := XML.Next_Sibling (R);
            end loop;
         end;

         if not WSDL.Is_Standard (-Base)
           or else (To_Type (-Base) = P_Character
                    and then not Is_Character (N, -Base, Document))
         then
            N := Look_For_Schema (N, -Base, Document);

            if N = null then
               raise WSDL_Error
                 with "Definition for " & (-Base) & " not found.";

            else
               O.No_Param := True;
               Parse_Element (O, N, Document);
               O.No_Param := False;
            end if;
         end if;

         return Build_Derived (-Name, -Base, C, N);
      end if;
   end Parse_Simple;

   --------------------------
   -- Register_Name_Spaces --
   --------------------------

   procedure Register_Name_Spaces (N : DOM.Core.Node) is
      Atts : constant DOM.Core.Named_Node_Map :=
               DOM.Core.Nodes.Attributes (N);
   begin
      for K in 0 .. DOM.Core.Nodes.Length (Atts) - 1 loop
         declare
            N      : constant DOM.Core.Node := DOM.Core.Nodes.Item (Atts, K);
            N_Name : constant String := DOM.Core.Nodes.Node_Name (N);
         begin
            if N_Name'Length > 6
              and then N_Name (N_Name'First .. N_Name'First + 5) = "xmlns:"
            then
               --  We can have multiple prefix pointing to the same URL
               --  (namespace). But an URL must be unique

               WSDL.Name_Spaces.Register
                 (DOM.Core.Nodes.Local_Name (N),
                  DOM.Core.Nodes.Node_Value (N));

               if not WSDL.Name_Spaces.Contains
                 (DOM.Core.Nodes.Node_Value (N))
               then
                  WSDL.Name_Spaces.Register
                    (DOM.Core.Nodes.Node_Value (N),
                     DOM.Core.Nodes.Local_Name (N));
               end if;
            end if;
         end;
      end loop;
   end Register_Name_Spaces;

   ---------------------
   -- Skip_Annotation --
   ---------------------

   procedure Skip_Annotation (N : in out DOM.Core.Node) is
   begin
      if N /= null
        and then Utils.No_NS (DOM.Core.Nodes.Node_Name (N)) = "annotation"
      then
         N := XML.Next_Sibling (N);
      end if;
   end Skip_Annotation;

   -----------
   -- Style --
   -----------

   function Style (O : Object'Class) return Message.Binding_Style is
   begin
      return O.Style;
   end Style;

   -----------
   -- Trace --
   -----------

   procedure Trace (Message : String; N : DOM.Core.Node) is
   begin
      if Verbose_Mode = 2 then
         Text_IO.Put_Line (Message);

         if N = null then
            Text_IO.Put_Line ("   Node is null.");
         else
            declare
               Name : constant String :=
                        DOM.Core.Nodes.Local_Name (N);
               Atts : constant DOM.Core.Named_Node_Map :=
                        DOM.Core.Nodes.Attributes (N);
            begin
               Text_IO.Put_Line ("   " & Name);

               for K in 0 .. DOM.Core.Nodes.Length (Atts) - 1 loop
                  Text_IO.Put ("      ");
                  declare
                     N     : constant DOM.Core.Node :=
                               DOM.Core.Nodes.Item (Atts, K);
                     Name  : constant String := DOM.Core.Nodes.Local_Name (N);
                     Value : constant String := DOM.Core.Nodes.Node_Value (N);
                  begin
                     Text_IO.Put (Name & " = " & Value);
                  end;
                  Text_IO.New_Line;
               end loop;
            end;
         end if;
      end if;
   end Trace;

   -------------
   -- Verbose --
   -------------

   procedure Verbose (Level : Verbose_Level := 1) is
   begin
      Verbose_Mode := Level;
   end Verbose;

end SOAP.WSDL.Parser;
