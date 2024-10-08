module InputPosition exposing (InputPosition(..), 
 deltaKeyboardPos, update, updateNoKeyboard, computeKeyboardPos)

import Msg exposing (Msg(..))
import Geometry.Point exposing (Point)
import Polygraph as Graph
import HtmlDefs exposing (Key(..))

type InputPosition
    = InputPosMouse
    | InputPosKeyboard ( Int, Int )
    | InputPosGraph Graph.Id

     {- let offsetPos x y =
                             let (curx, cury) = getKeyboardPos st2.pos in
                             { st2 | pos = InputPosKeyboard (x + curx, y + cury)}
                   in                   
                   (case msg of
                     MouseMove _ -> { st2 | pos = InputPosMouse }
                     KeyChanged False _ (Character 'h') -> offsetPos -1 0
                     KeyChanged False _ (Character 'j') -> offsetPos 0 1
                     KeyChanged False _ (Character 'k') -> offsetPos 0 -1
                     KeyChanged False _ (Character 'l') -> offsetPos 1 0
                     
                     _ -> st2
                   )  -}



-- offsetKeyboardPos = 200



deltaKeyboardPos : Int -> (Int, Int) -> Point
deltaKeyboardPos offsetKeyboardPos (x, y) =
   (toFloat (x * offsetKeyboardPos), toFloat (y * offsetKeyboardPos))

getKeyboardPos : InputPosition -> (Int, Int)
getKeyboardPos pos =
    case pos of       
       InputPosKeyboard p -> p
       _  -> (0, 0)

computeKeyboardPos : Point -> Int -> Point -> InputPosition
computeKeyboardPos (originx, originy) offsetKeyboardPos (posx, posy) =
    let size = toFloat offsetKeyboardPos in
    let diff z1 z2 = floor (z2 / size) - floor (z1 / size) in
    let (x, y) = (diff originx posx, diff originy posy) in
    InputPosKeyboard (x, y)



update : InputPosition -> Msg -> InputPosition
update pos msg =
     let offsetPos x y =
               let (curx, cury) = getKeyboardPos pos in
                InputPosKeyboard (x + curx, y + cury)
     in                   
     (case msg of      
       KeyChanged False _ (Character 'h') -> offsetPos -1 0
       KeyChanged False _ (Character 'j') -> offsetPos 0 1
       KeyChanged False _ (Character 'k') -> offsetPos 0 -1
       KeyChanged False _ (Character 'l') -> offsetPos 1 0       
       _ -> updateNoKeyboard pos msg
     ) 

updateNoKeyboard : InputPosition -> Msg -> InputPosition
updateNoKeyboard pos msg =                   
     case msg of
       MouseMove _ -> InputPosMouse
       MouseOn id ->  InputPosGraph id       
       _ -> pos
      