module ArrowStyle exposing (ArrowStyle, empty, {- keyUpdateStyle, -} quiverStyle,
   tikzStyle, tailToString , tailFromString,
   headToString, headFromString, 
   alignmentToString, alignmentFromString, 
   makeHeadTailImgs, isDouble, doubleSize,
   controlChars,
   toggleDashed, dashedStr, -- PosLabel(..),
   -- quiver
    keyMaybeUpdateStyle,
    keyMaybeUpdateColor)

import HtmlDefs exposing (Key(..))

import Geometry.Point as Point exposing (Point)

import String.Svg as Svg
import String.Html
import Drawing.Color as Color exposing (Color)
import Geometry.QuadraticBezier exposing (QuadraticBezier)
import Geometry.Epsilon exposing (norm0, epsilon)
import Geometry exposing (LabelAlignment(..))
import Json.Encode as JEncode
import List.Extra as List
import ListExtraExtra exposing (nextInList)
imgDir : String
imgDir = "img/arrow/"

-- following the tikzcd-editor
dashedStr : String
dashedStr = "7, 3"

-- from GridCellArrow in tikz-cd editor
imgWidth : Float
imgWidth = 9.764

imgHeight : Float
imgHeight = 13

doubleSize = 2.5

{-}
type PosLabel =
     DefaultPosLabel
   | LeftPosLabel
   | RightPosLabel -}
type alias Style = { tail : TailStyle, 
                     head : HeadStyle, double : Bool, 
                     dashed : Bool, bend : Float,
                     labelAlignment : LabelAlignment,
                     -- betweeon 0 and 1, 0.5 by default
                     labelPosition : Float,
                     color : Color
                    } 
type alias ArrowStyle = Style

tailToString : TailStyle -> String
tailToString tail =
   case tail of
         DefaultTail -> "none"
         Hook -> "hook"
         HookAlt -> "hookalt"
         Mapsto -> "mapsto"
tailFromString : String -> TailStyle
tailFromString tail =
   case tail of         
         "hook" -> Hook
         "hookalt" -> HookAlt
         "mapsto" -> Mapsto
         _ -> DefaultTail

headToString : HeadStyle -> String
headToString head =
  case head of
       DefaultHead -> "default" 
       TwoHeads    -> "twoheads" 
       NoHead      -> "none"

headFromString : String -> HeadStyle
headFromString head =
  case head of        
       "twoheads" -> TwoHeads    
       "none" -> NoHead      
       _ -> DefaultHead

alignmentToString : LabelAlignment -> String
alignmentToString tail =
   case tail of
         Centre -> "centre"
         Over -> "over"
         Left -> "left"
         Right -> "right"
alignmentFromString : String -> LabelAlignment
alignmentFromString tail =
   case tail of         
         "centre" -> Centre
         "right" -> Right
         "over" -> Over
         _ -> Left

empty : Style
empty = { tail = DefaultTail, head = DefaultHead, double = False, dashed = False,
          bend = 0, labelAlignment = Left,
          labelPosition = 0.5, color = Color.black }

isDouble : Style -> Basics.Bool
isDouble { double } = double
  

type HeadStyle = DefaultHead | TwoHeads | NoHead
type TailStyle = DefaultTail | Hook | HookAlt | Mapsto






toggleHead : Style -> Style
toggleHead s =  { s | head = nextInList [DefaultHead, NoHead, TwoHeads] s.head }

toggleHook : Style -> Style
toggleHook s =  
        { s | tail = nextInList [Hook, HookAlt, DefaultTail] s.tail }

toggleMapsto : Style -> Style
toggleMapsto s =  { s | tail = nextInList [Mapsto, DefaultTail] s.tail }


toggleLabelAlignement : Style -> Style
toggleLabelAlignement s =  
        { s | labelAlignment = nextInList [Left, Right]
        -- , Centre, Over] 
        -- the other ones do not seem to work properly
        s.labelAlignment }


toggleDouble : Style -> Style
toggleDouble s = { s | double = not s.double }
  
toggleDashed : Style -> Style
toggleDashed s = { s | dashed = not s.dashed }

prefixDouble : Style -> String
prefixDouble { double } = 
  if double then "double-" else ""

headFileName : Style -> String
headFileName s = 
  prefixDouble s
   ++ 
   headToString s.head ++ ".svg"
     
tailFileName : Style -> String
tailFileName s =
  prefixDouble s
   ++ tailToString s.tail ++ ".svg"


type alias Svg a = Svg.Svg a
type alias SvgAttribute a = String.Html.Attribute a
     

svgRotate : Point -> Float -> SvgAttribute a
svgRotate (x2, y2) angle = 
     Svg.transform <|         
        " rotate(" ++ String.fromFloat angle 
          ++ " " ++ String.fromFloat x2
          ++ " " ++ String.fromFloat y2 ++ ")"

makeImg : Point -> Float -> String -> Svg a
makeImg (x,y) angle file =
     let (xh, yh) = (x - imgHeight / 2, y - imgHeight / 2) in
     let f = String.fromFloat in
     Svg.image
          ([Svg.xlinkHref <| imgDir ++ file,
          Svg.x <| f xh,
          Svg.y <| f yh,
          Svg.width <| f imgWidth,
          Svg.height <| f imgHeight,
          svgRotate (x,y) angle]          
          )
           []

makeHeadTailImgs : QuadraticBezier -> Style -> List (Svg a)
makeHeadTailImgs {from, to, controlPoint} style =
   
    let angle delta =  Point.pointToAngle delta * 180 / pi in
     
    -- let mkImg = makeImg from to angle in
    [ makeImg to (angle <| Point.subtract to controlPoint) 
       <| headFileName style,
      makeImg from (angle <| Point.subtract controlPoint from) 
       <| tailFileName style ]


-- chars used to control in keyUpdateStyle
controlChars = "|>(=-bBA]["
maxLabelPosition = 0.9
minLabelPosition = 0.1

-- doesn't update the color
keyMaybeUpdateStyle : Key -> Style -> Maybe Style
keyMaybeUpdateStyle k style = 
   case k of 
        Character '|' -> Just <| toggleMapsto style
        Character '>' -> Just <| toggleHead style
        Character '(' -> Just <| toggleHook style
        Character '=' -> Just <| toggleDouble style
        Character '-' -> Just <| toggleDashed style
        Character 'b' -> Just <| {style | bend = style.bend + 0.1 |> norm0}
        Character 'B' -> Just <| {style | bend = style.bend - 0.1 |> norm0}
        Character 'A' -> Just <| toggleLabelAlignement style
        Character ']' -> if style.labelPosition + epsilon >= maxLabelPosition then Nothing else
               Just {style | labelPosition = style.labelPosition + 0.1 |> min maxLabelPosition}
        Character '[' -> 
               if style.labelPosition <= minLabelPosition + epsilon then Nothing else
               Just {style | labelPosition = style.labelPosition - 0.1 |> max minLabelPosition}
        _ -> Nothing

keyMaybeUpdateColor : Key -> Style -> Maybe Style
keyMaybeUpdateColor k style =
   case k of 
      Character c ->
         -- let _ = Debug.log "char" c in 
         Color.fromChar c
         |> Maybe.andThen 
            (\ color -> if color == style.color then Nothing else 
                        Just { style | color = color})
      _ -> Nothing

--keyUpdateStyle : Key -> Style -> Style
--keyUpdateStyle k style = keyMaybeUpdateStyle k style |> Maybe.withDefault style


quiverStyle : ArrowStyle -> List (String, JEncode.Value)
quiverStyle st =
   let { tail, head, double, dashed } = st in
   let makeIf b x = if b then [x] else [] in
   let headStyle = case head of 
          DefaultHead -> []       
          TwoHeads -> [("head", [("name", "epi")])]
          NoHead -> [("head", [("name", "none")])]
   in
   let tailStyle = case tail of 
          DefaultTail -> []
          Mapsto -> [("tail", [("name", "maps to")])]
          Hook -> [("tail", [("name", "hook"),("side", "top")])]
          HookAlt -> [("tail", [("name", "hook"),("side", "bottom")])]
   in
   let style = List.map (\(x,y) -> (x, JEncode.object <| List.map (\(s, l) -> (s, JEncode.string l)) y)) <|
               headStyle
               ++
               tailStyle ++
               (makeIf dashed ("body", [("name", "dashed")]))
   in
   (makeIf double ("level", JEncode.int 2))  
   ++ [("style", JEncode.object style )]
   ++ (makeIf (st.bend /= 0) ("curve", JEncode.int <| floor (st.bend * 10)))
   ++ (makeIf (st.labelPosition /= 0.5) ("label_position", JEncode.int <| floor (st.labelPosition * 100)))

-- from Quiver
{-type LabelAlignment =
    Centre
  | Over
  | Left 
  | Right
  -}

headTikzStyle : HeadStyle -> String
headTikzStyle hd =
    case hd of
            DefaultHead -> "->, "
            TwoHeads -> "onto, "
            NoHead -> "-,"

tikzStyle : ArrowStyle -> String
tikzStyle stl =
    "fore, " ++
    Color.toString stl.color ++ "," ++
        (case (stl.head, stl.double) of
            (NoHead, True) -> "identity, "
            (hd, True) -> (headTikzStyle hd) ++ "cell=0.2, "
            (hd, False) -> (headTikzStyle hd)
       )
    ++ (if stl.dashed then "dashed, " else "")
    ++ (if stl.bend /= 0 then
           "curve={ratio=" ++ String.fromFloat stl.bend ++ "}, "
        else "")
    ++ (case stl.tail of
         DefaultTail -> ""
         Mapsto -> "mapsto, "
         Hook -> "into, "
         HookAlt -> "linto, ")
        
