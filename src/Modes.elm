module Modes exposing (..)

import ArrowStyle exposing (ArrowStyle)
import Geometry.Point exposing (Point)
import Polygraph as Graph exposing (EdgeId, NodeId)
import QuickInput exposing (NonEmptyChain)
import InputPosition exposing (InputPosition)
import GraphDefs


type Mode
    = DefaultMode
    | NewArrow NewArrowState
    | Move MoveState
      -- the list of ids to be edited
    | RenameMode String (List Graph.Id)
    | DebugMode
    | NewNode
    | QuickInputMode (Maybe NonEmptyChain)
    | SquareMode SquareState
    | RectSelect Point Bool -- keep previous selection?
      -- | SplitArrow EdgeId
    | SplitArrow SplitArrowState

type alias MoveState = 
   { orig : Point,  -- mouse original point at the beginning of the move mode
     -- this was used to compute the move relative to this point, but this
     -- is no longer used
      pos : InputPosition, 
    merge : Bool }

type alias SplitArrowState =
    { chosenEdge : EdgeId
    , source : Graph.Id
    , target : Graph.Id
    , pos : InputPosition
    , label : GraphDefs.EdgeLabel -- original edge label
    , labelOnSource : Bool -- shall we transfer the existing label from the source
    }





type alias NewArrowState =
    { chosenNode : NodeId, style : ArrowStyle, pos : InputPosition, inverted : Bool }


type alias SquareState =
    { chosenNode : NodeId
    , n1 : NodeId
    , n1ToChosen : Bool
    , e1 : EdgeId
    , n2 : NodeId
    , n2ToChosen : Bool
    , e2 : EdgeId

    --   next possibility of square to be tested
    , configuration : Int
    }
