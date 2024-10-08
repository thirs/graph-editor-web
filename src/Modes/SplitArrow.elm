module Modes.SplitArrow exposing (fixModel, graphDrawing, initialise, update, help)



-- import Graph exposing (..)

import Polygraph as Graph exposing (Graph, NodeId, EdgeId)
import Maybe
import IntDict
import Msg exposing (Msg(..))
import HtmlDefs exposing (Key(..), computeLayout)
import GraphDefs exposing (NodeLabel, EdgeLabel, EdgeType(..))

import Modes exposing ( Mode(..), SplitArrowState)
import Model exposing (..)
import InputPosition exposing (InputPosition(..))

import GraphDrawing exposing (NodeDrawingLabel, EdgeDrawingLabel)
import Geometry.Point exposing (Point)
import CommandCodec exposing (protocolSendGraphModif)
import CommandCodec exposing (protocolSendModif, protocolSend)
import Format.GraphInfo as GraphInfo



isValid : Model -> SplitArrowState -> Bool
isValid model {chosenEdge, source, target} =
   Graph.existsAll (getActiveGraph model)
      [chosenEdge, source,target]
  
fixModel : Model -> SplitArrowState -> Model
fixModel model state =
  if isValid model state then model else {model | mode = DefaultMode }
   

initialise : Model -> ( Model, Cmd Msg )
initialise m =
    let modelGraph = (getActiveGraph m) in
    GraphDefs.selectedEdgeId modelGraph
    |> Maybe.andThen (\id ->      
        Graph.getEdge id modelGraph
        |> Maybe.andThen (\ e -> 
          GraphDefs.filterNormalEdges e.label.details
          |> Maybe.map (\ l -> 
            noCmd {m | mode = SplitArrow 
                   { chosenEdge = id, source = e.from, target = e.to, 
                     pos = InputPosMouse,
                     label = GraphDefs.mapDetails (always l) e.label,
                     labelOnSource = True,
                     guessPos = True}
                   })))
        
        -- |> Maybe.map
        -- -- prevent bugs (if the mouse is thought
        -- -- to be kept on a point)
        --    (Tuple.mapFirst (\model -> { model | mousePointOver = ONothing}))
        |> Maybe.withDefault (switch_Default m)






nextStep : Model -> Bool -> SplitArrowState -> ( Model, Cmd Msg )
nextStep model finish state =
         
    let
        info =
            stateInfo finish model state
    in
    -- let finalGraph = setSelModif info.movedNode info.graph in
    let finalGraph = info.graph in
     if finish then ({ model | mode = DefaultMode }, 
        protocolSendGraphModif model.graphInfo Msg.defaultModifId finalGraph)
     --computeLayout())  
    else
        let ne1 = (info.ne1, info.le1)
            ne2 = (info.ne2, info.le2)
        in
        let tabId = model.graphInfo.activeTabId in
        let ids = 
              (if info.created then 
                [ (info.movedNode, info.movedLabel
                   --GraphDefs.getLabelLabel info.movedNode info.graph
                   --|> Maybe.withDefault ""
                   ),
                  ne1, ne2 ]
              else
                 [ ne1, ne2 ])
              |>
              List.map (\ (id, label) -> 
                {id = id, label = Just label, tabId = tabId}
              )
        in
        let (nextModel, idModif) = popIdModif model in
        ({nextModel | mode = DefaultMode}, 
        protocolSend
        { id =  idModif 
        , modif = GraphInfo.activeGraphModifHelper nextModel.graphInfo finalGraph
        , selIds = IntDict.empty
        , command = Msg.RenameCommand ids
         })
        -- Modes.Rename.newState finalGraph ids model.graphInfo
        
        -- (initialise_RenameModeWithDefault False ids m2, computeLayout ())
                          



-- for view







-- movedNode

type alias Info = { graph : Graph.ModifHelper NodeLabel EdgeLabel,
                    movedNode : NodeId ,  
                    movedLabel : String,                  
                    created : Bool,
                    ne1 : EdgeId,
                    ne2 : EdgeId,
                    -- default label for renaming
                    le1 : String,
                    -- default label for renaming
                    le2 : String }

guessPosition : Model -> SplitArrowState -> Point
guessPosition m s = 
     case Graph.getNodes [s.source, s.target] (getActiveGraph m)
                        |> List.map (.label >> .pos)  of
       [p1, p2] -> Geometry.Point.middle p1 p2
       _ -> m.mousePos

stateInfo : Bool -> Model -> SplitArrowState -> Info
stateInfo finish m state =
    let modelGraph = getActiveGraph m in
    let otherLabel = 
              (getActiveGraph m) |> GraphDefs.getLabelLabel 
              (if state.labelOnSource then 
                 state.target 
               else 
                 state.source)
                |> Maybe.withDefault ""
    in
    let
        ( ( g, n ), created ) =
          let makeInfo pos = mayCreateTargetNodeAt m pos otherLabel finish in
           if state.guessPos then
             makeInfo (guessPosition m state)
           else
            case state.pos of
              InputPosGraph id -> ((Graph.newModif modelGraph, id), False)
              _ -> makeInfo m.mousePos                              
           
    in
    let ((l1, d1), (l2, d2)) = 
           let existingLabels = (GraphDefs.mapDetails NormalEdge state.label, state.label.details.label) in
           let newLabel = (GraphDefs.emptyEdge, otherLabel) in                  
           if state.labelOnSource then 
             (existingLabels, newLabel)
           else
             (newLabel, existingLabels)
    in
    let (g1, ne1) = (Graph.md_newEdge g state.source n l1) in
    let (g2, ne2) = (Graph.md_newEdge g1 n state.target l2) in
    -- TODO: it would be more efficient to just move the source/target of the chosenEdge
    { graph = Graph.md_merge (if state.labelOnSource then ne1 else ne2) state.chosenEdge g2,
      created = created,
      movedNode = n,
      movedLabel = otherLabel,
      ne1 = ne1,
      le1 = d1,
      ne2 = ne2,
      le2 = d2 }
   





graphDrawing : Model -> SplitArrowState -> Graph NodeDrawingLabel EdgeDrawingLabel
graphDrawing m state =
    let
        info =
            stateInfo False m state
    in
    collageGraphFromGraph m <| Graph.applyModifHelper info.graph        


update : SplitArrowState -> Msg -> Model -> ( Model, Cmd Msg )
update state msg model =
    let next finish = nextStep model finish state in
    let updateState st = { model | mode = SplitArrow st } in
    let updatePos st = InputPosition.updateNoKeyboard st.pos msg in
    case msg of  
        KeyChanged False _ (Character '?') -> noCmd <| toggleHelpOverlay model
        KeyChanged False _ (Control "Escape") -> switch_Default model
        KeyChanged False _ (Character '/') -> noCmd <| updateState
           { state | labelOnSource = not state.labelOnSource } 
        MouseClick -> next False          
        KeyChanged False _ (Control "Enter") -> next True
    --     TabInput -> Just <| ValidateNext
        KeyChanged False _ (Control "Tab") -> next False
        _ ->
           let newPos = InputPosition.updateNoKeyboard state.pos msg in
           let guessPos = case (msg, newPos) of 
                      (MouseMove _, _) -> False
                      (_, InputPosMouse) -> state.guessPos
                      _ -> False                      
           in          
           
            noCmd 
             <| updateState 
             { state | pos = newPos, guessPos = guessPos } 
           
help : String
help =
            "[ESC] cancel, " ++
            HtmlDefs.overlayHelpMsg 
            ++ ", [click] name the point (if new), "
            ++ "[/] to move the existing label on the other edge, "
            ++ "[RET] terminate the square creation"             
             
      