module Modes.CutHead exposing (update, graphDrawing, help, initialise, fixModel)
import Modes exposing (CutHeadState, Mode(..), MoveDirection(..))
import Modes.Move
import Model exposing (Model, {- setActiveGraph, setSaveGraph, -} noCmd, toggleHelpOverlay, getActiveGraph)
import Msg exposing (Msg(..), Command(..))
import Polygraph as Graph exposing (Graph)
import HtmlDefs exposing (Key(..))
import GraphDefs exposing (NodeLabel, EdgeLabel, edgeToNodeLabel)
import InputPosition exposing (InputPosition(..))
import Zindex
import GraphDrawing exposing (NodeDrawingLabel, EdgeDrawingLabel)
import Format.GraphInfo exposing (Modif(..))
import CommandCodec exposing (protocolSendGraphModif)
import Format.GraphInfo exposing (activeGraphModif)
import CommandCodec exposing (updateModifHelper)

fixModel : Model -> CutHeadState -> Model
fixModel model state =
   let modelGraph = getActiveGraph model in
   case Graph.getEdge state.edge.id modelGraph of 
     Nothing -> {model | mode = DefaultMode }
     Just edge -> {model | mode = CutHead {state | edge = edge}}


initialise : Model -> Model
initialise model =
   let modelGraph = getActiveGraph model in
   case GraphDefs.selectedEdge modelGraph of
      Nothing -> model
      Just e -> if GraphDefs.isPullshout e.label then model else 
                 {  model | mode = CutHead { edge = e,head = True, duplicate = False } }   

help : String 
help =          HtmlDefs.overlayHelpMsg
                ++ ", [RET] or [click] to confirm, [ctrl] to merge. [ESC] to cancel. "
                ++ "[c] to switch between head/tail"                
                ++ ", [d] to duplicate (or not) the arrow."

update : CutHeadState -> Msg -> Model -> (Model, Cmd Msg)
update state msg m =
  let finalise merge = 
         let info = makeGraph merge state m in
         updateModifHelper {m | mode = DefaultMode} info.graph
         -- (setSaveGraph {m | mode = DefaultMode} info.graph, Cmd.none)
         -- computeLayout())
  in
  let changeState s = { m | mode = CutHead s } in
  case msg of
        KeyChanged False _ (Character '?') -> noCmd <| toggleHelpOverlay m
        KeyChanged False _ (Control "Escape") -> ({ m | mode = DefaultMode}, Cmd.none)
        KeyChanged False _ (Control "Enter") -> finalise False
        KeyChanged True _ (Control "Control") -> finalise True
        MouseClick -> finalise False
        KeyChanged False _ (Character 'c') -> (changeState { state | head = (not state.head)} , Cmd.none)
        KeyChanged False _ (Character 'd') -> (changeState { state | duplicate = (not state.duplicate)} , Cmd.none)
        _ -> noCmd m

graphDrawing : Model -> CutHeadState -> Graph NodeDrawingLabel EdgeDrawingLabel
graphDrawing m state = 
  makeGraph False state m |> Modes.Move.computeGraph 
  |> GraphDrawing.toDrawingGraph

-- TODO: factor with newArrow.moveNodeInfo
makeGraph  : Bool -> CutHeadState -> Model -> 
   { graph : Graph.ModifHelper NodeLabel EdgeLabel, 
   weaklySelection : Maybe Graph.Id }
makeGraph merge {edge, head, duplicate} model =
   let modelGraph = getActiveGraph model in
   let modifGraph = Graph.newModif modelGraph in
   let pos = model.mousePos in
   let (id1, id2) = if head then (edge.from, edge.to) else (edge.to, edge.from) in
   let nodeLabel = Graph.get id2
         (\label -> {label | pos = pos})(edgeToNodeLabel pos)
         modelGraph |> 
         Maybe.withDefault (GraphDefs.newNodeLabel pos "" True Zindex.defaultZ )
   in
   let extGraph =  Graph.md_makeCone modifGraph [id1] nodeLabel edge.label (not head) in
    let g4 = 
         if duplicate then 
            extGraph.extendedGraph
            -- GraphDefs.unselect edge.id extGraph.extendedGraph 
         else
            List.foldl (\ id -> Graph.md_merge id edge.id) extGraph.extendedGraph
            extGraph.edgeIds
    in
   let moveInfo =
         Modes.Move.mkGraph model InputPosMouse Free merge g4 
          modelGraph
          extGraph.newSubGraph 
   in
    {graph = moveInfo.graph, weaklySelection = moveInfo.weaklySelection} -- .graph
