port module Main exposing (main)
-- TODO: avoir mode dans Model, et separer le fichier state de Square
-- move: with keyboard
-- copier ?


-- https://package.elm-lang.org/packages/mpizenberg/elm-pointer-events/4.0.2/Html-Events-Extra-Mouse
-- mouseclick prevent default?
-- split arrow, copy arrow
-- when saving, clean the graph
-- hover for bent lines
-- tab: prevent default
-- bug avec square
-- ctrl pour merge,
-- et close commutation
-- touche pour guess labels (s'il  a plusieurs possiblites')


import Html.Events.Extra.Mouse as MouseEvents

import Model exposing (..)
import Browser
import Browser.Events as E

import Task
import Time
import Browser.Dom as Dom
import Process


import Json.Decode as D
import Json.Encode as JE
import Polygraph as Graph exposing (Graph, NodeId, Node, Edge)

import Drawing exposing (Drawing)

import Geometry.Point as Point exposing (Point)

import Html exposing (Html)
import Html.Attributes
import Html.Events
import Maybe.Extra as Maybe
import IntDict
import Unification

import Parser exposing ((|.), (|=), Parser)
import Set
import QuickInput exposing (equalityParser)

import GraphDrawing exposing (..)
import Msg exposing (Msg(..), Scenario(..),
   LoadGraphInfo, mapLoadGraphInfo, scenarioOfString, 
   loadGraphInfoToMsg)

import Tuple exposing (first, second)
import Maybe exposing (withDefault)

import Modes.Square
import Modes.NewArrow 
import Modes.NewLine
import Modes.SplitArrow
import Modes.Pullshout
import Modes.CutHead
import Modes.Move
import Drawing.Color as Color
import Modes exposing (Mode(..), MoveMode(..), MoveDirection(..), isResizeMode, ResizeState, EnlargeState)

import ArrowStyle

import HtmlDefs exposing (Key(..), computeLayout)
import GraphDefs exposing (NodeLabel, EdgeLabel)
import GraphDefs exposing (newNodeLabel, MaybeProofDiagram(..), coqProofTexCommand, MaybeChain(..))
import Tikz exposing (graphToTikz)
import Html
import Html.Events
import InputPosition exposing (InputPosition(..))
import Geometry
import Geometry.Point
import Format.Version0
import Format.Version1
import Format.Version2
import Format.Version3
import Format.Version4
import Format.Version5
import Format.Version6
import Format.Version7
import Format.Version8
import Format.Version9
import Format.Version10
import Format.Version11
import Format.Version12
import Format.LastVersion as LastFormat

import Format.GraphInfo as GraphInfo exposing (Tab)

import List.Extra
import GraphDefs exposing (exportQuiver)
import GraphProof
import GraphDrawing
import String.Svg
import Zindex exposing (defaultZ, foregroundZ)
import Geometry.Point as Point
import GraphDefs exposing (isProofLabel)


port preventDefault : JE.Value -> Cmd a
port onKeyDownActive : (JE.Value -> a) -> Sub a


port clear : ({scenario : String, preamble: String} -> a) -> Sub a

-- tell js to save the graph, version  is the format version
type alias JsGraphInfo = { graph : LastFormat.Graph, version : Int }
type alias ExportFormats = {tex:String, svg:String, coq:String}

-- feedback: do we want a confirmation alert box?
port quicksaveGraph : { info : JsGraphInfo, export: ExportFormats, autosave : Bool} -> Cmd a
-- we ask js to save the graph
port saveGraph : {info: JsGraphInfo, export: ExportFormats} -> Cmd a
port makeSave : (() -> a) -> Sub a

port exportQuiver : JE.Value -> Cmd a
port alert : String -> Cmd a


port simpleMsg : (String -> a) -> Sub a

-- we ask js to open a graph file
port openFile : () -> Cmd a
port openDirectory : () -> Cmd a
-- or to retrieve the saved graph
port quickLoad : () -> Cmd a
-- js returns the graph
port loadedGraph0 : (LoadGraphInfo Format.Version0.Graph -> a) -> Sub a
port loadedGraph1 : (LoadGraphInfo Format.Version1.Graph -> a) -> Sub a
port loadedGraph2 : (LoadGraphInfo Format.Version2.Graph -> a) -> Sub a
port loadedGraph3 : (LoadGraphInfo Format.Version3.Graph -> a) -> Sub a
port loadedGraph4 : (LoadGraphInfo Format.Version4.Graph -> a) -> Sub a
port loadedGraph5 : (LoadGraphInfo Format.Version5.Graph -> a) -> Sub a
port loadedGraph6 : (LoadGraphInfo Format.Version6.Graph -> a) -> Sub a
port loadedGraph7 : (LoadGraphInfo Format.Version7.Graph -> a) -> Sub a
port loadedGraph8 : (LoadGraphInfo Format.Version8.Graph -> a) -> Sub a
port loadedGraph9 : (LoadGraphInfo Format.Version9.Graph -> a) -> Sub a
port loadedGraph10 : (LoadGraphInfo Format.Version10.Graph -> a) -> Sub a
port loadedGraph11 : (LoadGraphInfo Format.Version11.Graph -> a) -> Sub a
port loadedGraph12 : (LoadGraphInfo Format.Version12.Graph -> a) -> Sub a


-- port setFirstTabGrph : ()


-- we tell js about some mouse move event
port onMouseMove : JE.Value -> Cmd a
-- we then get back the relative position of the mouse
-- (this cannot be done in pure elm because it requires
-- to access to the currentTarget field of the event,
-- which is a js object)
port onMouseMoveFromJS : (Point -> a) -> Sub a

-- JS tells us that we received some paste event with such data
-- port onPaste : (String -> a) -> Sub a
-- we reply that we want to decode it
-- port decodeGraph : String -> Cmd a
-- JS would then calls us back with the decoded graph with loadGraph
-- port decodedGraph : (LastFormat.Graph -> a) -> Sub a


-- we receive a copy event
port onCopy : (() -> a) -> Sub a
-- we return the stuff to be written
port clipboardWriteGraph : JsGraphInfo -> Cmd a
-- statement
-- port incompleteEquation : { statement : String, script : String} -> Cmd a

-- we send a request to get a proof (by prompt?)
port requestProof : { statement : String, script : String} -> Cmd a

port applyProof : { statement : String, script : String} -> Cmd a
port appliedProof : ({ statement : String, script : String} -> a) -> Sub a

port toClipboard : { content:String, success: String, failure: String } -> Cmd a
port generateProofJs : { proof : String, graph : JsGraphInfo } -> Cmd a
port generateSvg : String -> Cmd a

-- ask js to prompt find and replace
port promptFindReplace : () -> Cmd a
-- it returns the data
port findReplace : ({ search: String, replace:String} -> a) -> Sub a

-- ask js to prompt Equation
port promptEquation : () -> Cmd a
-- return the equation
port promptedEquation : (String -> a) -> Sub a
port setFirstTabEquation : (String -> a) -> Sub a

-- ask js to prompt tab title
port promptTabTitle : String -> Cmd a
port promptedTabTitle : (String -> a) -> Sub a


port saveRulerGridSize : {gridSize:Int, rulerMargin:Int} -> Cmd a


-- number of ms between autosaves
autosaveTickMs : Float
autosaveTickMs = 60000


subscriptions : Model -> Sub Msg
subscriptions m = 
    Sub.batch 
     <|
    [
      makeSave (always Save),
      findReplace FindReplace,
      simpleMsg SimpleMsg,
      promptedTabTitle RenameTab,
      clear (\ {scenario, preamble} ->
          Clear {scenario = scenarioOfString scenario
               , preamble = preamble }),
      -- upload a graph (triggered by js)
      
      loadedGraph0  (mapLoadGraphInfo Format.Version0.fromJSGraph >> loadGraphInfoToMsg),
      loadedGraph1  (mapLoadGraphInfo Format.Version1.fromJSGraph >> loadGraphInfoToMsg),
      loadedGraph2  (mapLoadGraphInfo Format.Version2.fromJSGraph >> loadGraphInfoToMsg),
      loadedGraph3  (mapLoadGraphInfo Format.Version3.fromJSGraph >> loadGraphInfoToMsg),
      loadedGraph4  (mapLoadGraphInfo Format.Version4.fromJSGraph >> loadGraphInfoToMsg),
      loadedGraph5  (mapLoadGraphInfo Format.Version5.fromJSGraph >> loadGraphInfoToMsg),
      loadedGraph6  (mapLoadGraphInfo Format.Version6.fromJSGraph >> loadGraphInfoToMsg),
      loadedGraph7  (mapLoadGraphInfo Format.Version7.fromJSGraph >> loadGraphInfoToMsg),
      loadedGraph8  (mapLoadGraphInfo Format.Version8.fromJSGraph >> loadGraphInfoToMsg),
      loadedGraph9  (mapLoadGraphInfo Format.Version9.fromJSGraph >> loadGraphInfoToMsg),
      loadedGraph10 (mapLoadGraphInfo Format.Version10.fromJSGraph >> loadGraphInfoToMsg),
      loadedGraph11 (mapLoadGraphInfo Format.Version11.fromJSGraph >> loadGraphInfoToMsg),
      loadedGraph12 (mapLoadGraphInfo Format.Version12.fromJSGraph >> loadGraphInfoToMsg),
      setFirstTabEquation SetFirstTabEquation,
      -- decodedGraph (LastFormat.fromJSGraph >> PasteGraph),
      E.onClick (D.succeed MouseClick),
      -- completeEquation CompleteEquation,
      appliedProof AppliedProof
      {- Html.Events.preventDefaultOn "keydown"
        (D.map (\tab -> if tab then 
                            -- it is necessary to prevent defaults
                            -- otherwise the next immediate appearing input 
                            -- may not shows up
                                      (TabInput, True) 
                        else (Msg.noOp, False))
                         HtmlDefs.tabDecoder), -} ]
    ++
    if Msg.isSimpleScenario m.scenario then [] else
    (if m.autoSave then
        -- every minute
       [ Time.every autosaveTickMs (always MinuteTick) ]
    else [])
    ++
    (if m.scenario == Watch then [promptedEquation QuickInput]
    else [])
    -- ++
    -- (if m.mode == DefaultMode && m.mouseOnCanvas then
    --    [ onPaste (Do << decodeGraph)]
    --  else [])
    ++
    if case m.mode of
        ResizeMode _ -> False
        _ -> not m.mouseOnCanvas
    then [] 
    else
    (if m.scenario == Watch then [] else [promptedEquation QuickInput]
     -- is scenario is watch, we have already subscribed
    ) ++
    [ E.onKeyUp (D.map2 (KeyChanged False) HtmlDefs.keysDecoder HtmlDefs.keyDecoder),
      E.onKeyDown (D.map2 (KeyChanged True) HtmlDefs.keysDecoder HtmlDefs.keyDecoder),
      onCopy (always CopyGraph),
      
      onMouseMoveFromJS MouseMove,
      onKeyDownActive
           (\e -> e |> D.decodeValue (D.map2 ( \ks k -> 
               let checkCtrl =
                    if ks.ctrl && m.mode == DefaultMode then
                      Do <| preventDefault e
                    else Msg.noOp
               in
               case k of
                 Character '/' ->
                    case m.mode of
                      DefaultMode  -> Do <| preventDefault e
                      SplitArrow _ -> Do <| preventDefault e
                      _ -> Msg.noOp 
                 Character 'a' -> checkCtrl             
                 _ -> Msg.noOp
                
                )                
                HtmlDefs.keysDecoder
                HtmlDefs.keyDecoder)
                |> Result.withDefault Msg.noOp
                )
    ]












-- Model -----------------------------------------------------------------------





-- The graphs are updated according to the current mode





graph_RenameMode : List (Graph.Id, String) -> Model -> Graph NodeLabel EdgeLabel
graph_RenameMode l m =
   let g = getActiveGraph m in
   case l of
      [] -> g
      (id, s) :: _ ->   Graph.update id 
                        (\ n -> {n | label = s, isCoqValidated = False })  
                         (GraphDefs.mapNormalEdge (\e -> {e | label = s }))
                               g






{- switch_RenameMode : Model -> (Model, Cmd Msg)
switch_RenameMode model =
    let label : Maybe String
        label = case activeObj model of
              ONothing -> Nothing
              ONode id -> Graph.getNode id modelGraph |> Maybe.map .label
              OEdge id -> Graph.getEdge id modelGraph |> Maybe.map (\ (_, _, e) -> e.label)
    in
    case label of
        Nothing -> noCmd model
        Just l -> (
             {model | mode = RenameMode l}, Cmd.none {- focusLabelInput -})
 -}
-- Now, deal with incoming messages

toJsGraphInfo : Model -> JsGraphInfo
toJsGraphInfo model= { graph = LastFormat.toJSGraph 
                               <| GraphInfo.normalise  <| Model.toGraphInfo model,
                              -- fileName = model.fileName,
                              version = LastFormat.version}

updateIntercept : Msg -> Model -> (Model, Cmd Msg)
updateIntercept msg modeli =
  case modeli.scenario of
     Exercise1 -> 
        let nothing = noCmd modeli in
        case msg of
           MouseMove _  -> nothing
           MouseDown _ -> nothing
           NodeClick _ _ -> nothing
           EdgeClick _ _ -> nothing
           EltDoubleClick _ _ -> nothing
           MouseOn _ -> nothing
           MouseClick -> nothing
           _ -> update msg modeli
           
     _ -> update msg modeli

makeExports : Model -> ExportFormats
makeExports model = 
    let modelGraph = getActiveGraph model in
    let sizeGrid = getActiveSizeGrid model in
     {tex = Tikz.graphToTikz sizeGrid modelGraph
    , svg = svgExport model modelGraph
    , coq = coqExport model modelGraph }

-- TODO change the name
-- the suffix perform is to make the difference with the port name
setFirstTabEquationPerform : Model -> String -> (Model, Cmd Msg)
setFirstTabEquationPerform m s = 
   case Parser.run equalityParser s of
     Err _  -> noCmd m
     Ok chain -> 
        let mUpdated =
              updateFirstTab m <|
              \ t -> { t | graph = graphDrawingChain t.sizeGrid Graph.empty chain}
        in 
        ({ mUpdated | mode = DefaultMode}, computeLayout())

  

update : Msg -> Model -> (Model, Cmd Msg)
update msg modeli =
    let model = case msg of               
                SwitchTab i -> activateNthTab { modeli | mode = DefaultMode} i
                RenameTab s -> renameActiveTab { modeli | mode = DefaultMode} s
                RemoveTab -> removeActiveTabs { modeli | mode = DefaultMode}
                NewTab -> createNewTab { modeli | mode = DefaultMode} <| nextTabName modeli
                DuplicateTab -> duplicateTab { modeli | mode = DefaultMode} <| nextTabName modeli
                TabMoveLeft  -> moveTabLeft { modeli | mode = DefaultMode }
                TabMoveRight -> moveTabRight { modeli | mode = DefaultMode }
                KeyChanged _ r _ -> { modeli | specialKeys = r }
                MouseMoveRaw _ keys -> { modeli | specialKeys = keys, mouseOnCanvas = True} 
                MouseMove p -> { modeli | mousePos = p} -- , mouseOnCanvas = True}
                MouseDown e -> { modeli | specialKeys = e.keys }
                MouseLeaveCanvas -> 
                    { modeli | mouseOnCanvas = False }
                {- FindInitial -> selectInitial model -}
                LatexPreambleEdit s -> { modeli | latexPreamble = s }
                -- EditBottomText s -> 
                --     let _ = Debug.log "bottomText" model.bottomText in
                --     { model | bottomText = {- Debug.log "bottomText" -} s}
                       -- {model | mousePos = (x, y), statusMsg = "mouse " ++ Debug.toString (x, y)}
               -- KeyChanged False s -> {model | statusMsg = keyToString s}
               -- NodeClick n -> {model | statusMsg = "point " }
               -- NodeEnter n -> 
               --    let _ = Debug.log "ici" n in
               --   { model | mousePointOver = ONode n}
               -- NodeLeave n -> { model | mousePointOver = ONothing}
 
               -- MouseClick -> let _ = Debug.log "Mouse Click !" () in model
                _ -> modeli            
    in
    let modelGraph = getActiveGraph model in
    let sizeGrid = getActiveSizeGrid model in
    case msg of
     SetFirstTabEquation s -> setFirstTabEquationPerform modeli s
     Save -> (model, saveGraph { info = toJsGraphInfo model 
                              , export = makeExports model })
     RulerMargin rulerMargin -> noCmd {model | rulerMargin = rulerMargin}
     SaveRulerGridSize -> ({model | defaultGridSize = sizeGrid } , 
                  saveRulerGridSize {gridSize = sizeGrid
                                   , rulerMargin = model.rulerMargin}  )
        
     OptimalGridSize ->
          let selGraph = GraphDefs.selectedGraph modelGraph in
          case Graph.nodes selGraph of
            [n1, n2] ->
                let (x, y) = Point.subtract n1.label.pos n2.label.pos in         
                let newGridSize = round <| max (abs x) (abs y) in
                let m2 = pushHistory model in
                    noCmd <| setActiveSizeGrid m2 newGridSize
            _ -> noCmd model
     MinuteTick -> if model.autoSave then 
                         (model, quicksaveGraph 
                         { info = toJsGraphInfo model, export = makeExports model,
                         autosave = True }) 
                   else noCmd model
     Clear {scenario,preamble} -> 
        let modelf = clearModel model in
        let or s1 s2 = if s1 == "" then s2 else s1 in 
        noCmd { modelf | scenario = scenario,
            latexPreamble = or preamble modelf.latexPreamble
         }
         --  (iniModel, Task.attempt (always Msg.noyarn comOp) (Dom.focus HtmlDefs.canvasId))
     ToggleHideGrid -> noCmd {model | hideGrid = not model.hideGrid}     
     ToggleHideRuler -> noCmd {model | rulerShow = not model.rulerShow}  
     ToggleAutosave -> noCmd {model | autoSave = not model.autoSave}     
     ExportQuiver -> (model,  
                    exportQuiver <| 
                     GraphDefs.exportQuiver sizeGrid (GraphDefs.selectedGraph modelGraph))
     MouseMoveRaw v _ -> (model, onMouseMove v)
     NodeRendered n (x,y) ->
                -- let _ = Debug.log "nouvelle dims !" (n, dims) in
                let dims = (x, if y == 0 then 12 else y) in
                noCmd <|
                  updateActiveGraph model (Graph.updateNode n (\l -> {l | dims = Just dims }))
                
     EdgeRendered e (x, y) ->
                -- let _ = Debug.log "nouvelle dims !" (e, dims) in
                let dims = (x, if y == 0 then 12 else y) in
                noCmd <|
                   updateActiveGraph model
                      (GraphDefs.updateNormalEdge e (\l -> {l | dims = Just dims }))
     Do cmd -> (model, cmd)
     SimpleMsg s -> let modelf = clearModel model in
                     noCmd { modelf | scenario = SimpleScenario, statusMsg = s }
     SetFirstTab g ->
         let tab = getActiveTabInTabs g.tabs in
        (updateFirstTab model <| \t ->
                  { tab | title = t.title , active = t.active},
                 computeLayout ())
     Loaded g ->        
        let scenario = scenarioOfString g.scenario in
        let m =  clearHistory <| updateWithGraphInfo { model | 
                                              mode = DefaultMode, 
                                              scenario = scenario
                                            } g.graph 
        in
        let m2 =
                if scenario /= Exercise1 then m else
                { m | tabs = List.map (\t -> 
                  { t | graph = 
                      Graph.map 
                        (\ _ n -> { n | selected = String.contains "\\bullet" n.label})
                        (always identity) t.graph}
                    ) m.tabs
                }                
        in
        (m2,
                     -- we need drawn elements to resend their size
                                             computeLayout() )
     FindReplace req -> noCmd <| setSaveGraph model 
                          <| GraphDefs.findReplaceInSelected modelGraph req
     _ ->
      case model.mode of
        NewLine state -> Modes.NewLine.update state msg model
        DefaultMode -> update_DefaultMode msg model
        RectSelect orig -> update_RectSelect msg orig model.specialKeys.shift model
        EnlargeMode state -> update_Enlarge msg state model
        NewArrow astate -> Modes.NewArrow.update astate msg model
        PullshoutMode astate -> Modes.Pullshout.update astate msg model
            -- update_Modes.NewArrow astate msg m
        RenameMode b l -> update_RenameMode b l msg model
        Move s -> Modes.Move.update msg s model
        DebugMode -> update_DebugMode msg model
       -- NewNode -> update_NewNode msg model
        SquareMode state -> Modes.Square.update state msg model
        SplitArrow state -> Modes.SplitArrow.update state msg model
        CutHead state -> Modes.CutHead.update state msg model
        ResizeMode s -> update_Resize s msg model
        ColorMode ids -> update_Color ids msg model

update_Color : List Graph.EdgeId -> Msg -> Model -> (Model, Cmd Msg)
update_Color ids msg model =
    case msg of
        KeyChanged False _ (Character '?') -> noCmd <| toggleHelpOverlay model
        KeyChanged False _ (Control "Escape") ->
            switch_Default model
        KeyChanged False _ k ->
               let modelGraph = getActiveGraph model in
               case GraphDefs.updateStyleEdges 
                  (ArrowStyle.keyMaybeUpdateColor k)
                  (Graph.getEdges ids modelGraph)
                  modelGraph of 
                 Nothing -> noCmd model
                 Just g -> switch_Default <| setSaveGraph model g
        _ -> noCmd model


        
update_RenameMode : Bool -> List (Graph.Id, String) -> Msg -> Model -> (Model, Cmd Msg)
update_RenameMode save labels msg model =
   let edit_label s = 
         noCmd {model | mode = RenameMode save <| 
         case labels of
           (id, _) :: q -> (id, s) :: q
           _ -> labels -- should not happen
         }
   in 
    case msg of
      KeyChanged False _ (Control "Escape") -> switch_Default model
      KeyChanged False _ (Control "Enter") -> noCmd <| next_RenameMode True save labels model
      KeyChanged False _ (Control "Tab") -> noCmd <| next_RenameMode False save labels  model
    --   MouseClick -> finalise_RenameMode label model
      NodeLabelEdit _ s -> edit_label s
      EdgeLabelEdit _ s -> edit_label s
      _ -> noCmd model



next_RenameMode : Bool -> Bool -> List (Graph.Id, String) -> Model -> Model
next_RenameMode finish save labels model =
    let g = graph_RenameMode labels model in
    let m2 = if save then setSaveGraph model g else setActiveGraph model g in
    if finish then
      { m2 | mode = DefaultMode }
    else
      case labels of
        [] -> { m2 | mode = DefaultMode }
        [_] -> { m2 | mode = DefaultMode }
        _ :: q -> { m2 | mode = RenameMode save q }
        

update_RectSelect : Msg -> Point -> Bool -> Model -> (Model, Cmd Msg)
update_RectSelect msg orig keep model =
   case msg of
      KeyChanged False _ (Control "Escape") -> switch_Default model
      {- MouseUp -> switch_Default 
                  { model | graph = selectGraph model orig keep } -}
      MouseClick ->
          if model.mousePos == orig then
           switch_Default <| selectByClick model
          else
           switch_Default 
                <| setActiveGraph model <| selectGraph model orig keep
      -- au cas ou le click n'a pas eu le temps de s'enregistrer
      --   NodeClick n -> switch_Default { model | selectedObjs = [ONode n]} 
      --   EdgeClick n -> switch_Default { model | selectedObjs = [OEdge n]}
      _ -> noCmd model

update_Enlarge : Msg -> EnlargeState -> Model -> (Model, Cmd Msg)
update_Enlarge msg state model =
   let fin = switch_Default <| setSaveGraph model <| enlargeGraph model state in
   let updateState st = { model | mode = EnlargeMode st } in
   let updateDirection direction = noCmd <| updateState  { state | direction = direction} in
   case msg of
      KeyChanged False _ (Character '?') -> noCmd <| toggleHelpOverlay model
      KeyChanged False _ (Control "Escape") -> switch_Default model
      {- KeyChanged False _ (Character 's') -> 
                          noCmd <| { model | mode =
                                  EnlargeMode { state | onlySubdiag = not state.onlySubdiag }} -}
      MouseUp -> fin
      KeyChanged False _ (Character 'f') -> updateDirection Free
      KeyChanged False _ (Character 'x') -> updateDirection Horizontal
      KeyChanged False _ (Character 'y') -> updateDirection Vertical
      KeyChanged False _ (Control "Enter") -> fin
      -- au cas ou le click n'a pas eu le temps de s'enregistrer
      --   NodeClick n -> switch_Default { model | selectedObjs = [ONode n]} 
      --   EdgeClick n -> switch_Default { model | selectedObjs = [OEdge n]}
      _ -> noCmd <| { model | mode = EnlargeMode { state | pos = InputPosition.update state.pos msg }}

selectLoop : Bool -> Model -> Model
selectLoop direction model =
     let modelGraph = getActiveGraph model in
     let g = GraphDefs.toProofGraph modelGraph in
     let edges =  GraphDefs.selectedEdgeId modelGraph 
              |> Maybe.andThen (\id -> 
                   Graph.getEdge id g) -- |> Maybe.map (\ e -> { id = id, label = e.label}))
              |> Maybe.map (GraphProof.loopFrom direction g)
              |> Maybe.withDefault []
     in
     let diag = GraphProof.loopToDiagram edges in
    --  let _ = Debug.log "sel lhs" (diag.lhs |> List.map (.label >> .label)) in
    --  let _ = Debug.log "sel rhs" (diag.rhs |> List.map (.label >> .label)) in
    --  let _ = Debug.log "isBorder?" (GraphProof.isBorder diag) in     
       setActiveGraph model <|
             (edges |> List.map (Tuple.first >> .id)            
              |> List.foldl (\ e -> Graph.updateEdge e (\n -> {n | selected = True})) 
                  (GraphDefs.clearSelection modelGraph) )

rename : Model -> (Model, Cmd Msg)
rename model =
    let modelGraph = getActiveGraph model in
    let ids = GraphDefs.selectedId modelGraph 
            |> Maybe.map List.singleton 
            |> Maybe.withDefault []
    in
        noCmd <| initialise_RenameMode True ids model

latexToClipboard : String -> Cmd a
latexToClipboard tex =
   toClipboard {content = tex,
                success = "latex successfully copied.",
                failure = "unable to copy latex"
            }

generateProofString : Bool -> Graph NodeLabel EdgeLabel -> String
generateProofString debug g =
      let stToString = if debug then GraphProof.proofStatementToDebugString else GraphProof.proofStatementToString in
      let s = String.join "\n\n"
            <| List.map stToString 
            <| GraphProof.fullProofs
            <| GraphDefs.toProofGraph 
            g
      in
      s


graphQuickInput : Model -> QuickInput.Equation -> Graph NodeLabel EdgeLabel
graphQuickInput model (eq1, eq2) = 
  let modelGraph = getActiveGraph model in
  let sizeGrid = getActiveSizeGrid model in

  -- if an incomplete subdiagram is selected, we use it
  let od = GraphDefs.selectedIncompleteDiagram modelGraph in
  let default = graphDrawingChain sizeGrid modelGraph (eq1, eq2) in 
  let split l edges = GraphProof.isEmptyBranch l |> 
          Maybe.map (QuickInput.splitWithChain modelGraph edges) 
  in
  case od of
    Nothing -> default
    Just d ->           
        Maybe.or (split d.lhs eq2)
              (split d.rhs eq2)
                |> Maybe.withDefault default
               


update_DefaultMode : Msg -> Model -> (Model, Cmd Msg)
update_DefaultMode msg model =
    let delta_angle = pi / 5 in
    let modelGraph = getActiveGraph model in
    let sizeGrid = getActiveSizeGrid model in
    let move angle = 
               GraphDefs.selectedNode modelGraph                  
                 -- |> Maybe.andThen (\id -> Graph.getNode id modelGraph) 
                 |> Maybe.map (.label >> .pos)
                 |> Maybe.andThen (\p ->
                    Graph.filterNodes modelGraph 
                      (\ n -> n.pos /= p && (Point.subtract n.pos p |> Point.pointToAngle |>
                      Point.angleWithInRange delta_angle angle  ))
                    |>
                    List.Extra.minimumBy (.label >> .pos >> Point.distance p )                  
                
                 )
                 |> Maybe.map (\n ->
                 Model.addOrSetSel False n.id model
                 )                 
                 |> Maybe.withDefault model
                 |> noCmd
    in
    -- TODO: remove if not used
    let generateProof debug =

           let proof = generateProofString debug
                 <| GraphDefs.selectedGraph modelGraph
           in
           let json = toJsGraphInfo <| Model.restrictSelection model in
           (model, generateProofJs {proof = proof, graph = json}) 
                -- toClipboard 
                --   {content = s,
                --    success = "Proof successfully copied",
                --    failure = "Unable to copy" })
    in
    let weaklySelect id =
             noCmd <|              
                if model.specialKeys.shift then
                setActiveGraph model <| GraphDefs.addOrSetSel True id modelGraph
                else 
               -- if model.hoverId == Nothing then model else  
                setActiveGraph model <| GraphDefs.weaklySelect  
                                        id
                                         modelGraph                                          
    in
    let clearSel = noCmd <| setActiveGraph model 
                     <| GraphDefs.clearSelection modelGraph
    in
    let createPoint isMath label =
            let (newGraph, newId) = Graph.newNode modelGraph 
                    (newNodeLabel model.mousePos label isMath defaultZ)
                newModel = addOrSetSel False newId
                   <| setSaveGraph model newGraph                    
            in
            noCmd <| initialise_RenameMode False [ newId ] newModel
    in
    let increaseZBy offset =
           case GraphDefs.selectedId modelGraph of
              Nothing -> noCmd model
              Just id -> 
                    noCmd <| setSaveGraph model <|
                   Graph.update id 
                    (\ e -> { e | zindex = e.zindex + offset})
                    (\ e -> { e | zindex = e.zindex + offset})
                    modelGraph
    in
      
    
    {- let updateStr =
       GraphProof.proofStatementToString  -}
    -- Tuples.mapFirst (changeModel model) <|
    case msg of
        MouseOn id ->
              weaklySelect id
             
        MouseClick -> noCmd <| selectByClick model
        QuickInput s ->
          
              case Parser.run equalityParser s of
                  Err e -> noCmd <| {model | statusMsg = Parser.deadEndsToString e}
                  Ok chain ->
                    (Model.setSaveGraph model
                     <| graphQuickInput model chain, 
                     computeLayout ()                    
                     )
                           
          
           
        MouseMove _ -> 
             weaklySelect <| GraphDefs.closest model.mousePos modelGraph             
        MouseDown _ -> noCmd <| { model | mode = RectSelect model.mousePos }
        KeyChanged False _ (Control "Escape") -> clearSel
        KeyChanged False _ (Character '?') -> noCmd <| toggleHelpOverlay model
        KeyChanged False _ (Character 'w') -> clearSel
        KeyChanged False _ (Character 'e') ->
           noCmd <| initialiseEnlarge model
        KeyChanged False _ (Character 'E') ->
           (model, promptEquation ())
        KeyChanged False k (Character 'a') -> 
            if not k.ctrl then
              Modes.NewArrow.initialise model 
            else
              noCmd <| setActiveGraph model <| GraphDefs.selectAll modelGraph
        CopyGraph ->
              
              (model,
               clipboardWriteGraph <| 
               toJsGraphInfo <| Model.restrictSelection model
                --  { graph = LastFormat.toJSGraph 
                --     { tabs = [ {graph = GraphDefs.selectedGraph modelGraph
                --       , sizeGrid = sizeGrid, title = "", 
                --       active = True }]
                --       , latexPreamble = model.latexPreamble
                --       }
                --     , version = LastFormat.version }
                 )
        KeyChanged False _ (Character 'd') ->
            noCmd <| { model | mode = DebugMode }
        KeyChanged True _ (Character 'g') -> 
            let pressTimeoutMs = 100 in
            (Modes.Move.initialise True UndefinedMove model,
             Task.attempt (always PressTimeout) 
               <| Process.sleep pressTimeoutMs)
        KeyChanged False _ (Character 'i') -> 
           noCmd <| case GraphDefs.selectedEdgeId modelGraph of
                      Just id -> setSaveGraph model <| Graph.invertEdge id modelGraph
                      _ -> model
        {- KeyChanged False _ (Character 'I') -> noCmd <| selectInitial model -}
        {- KeyChanged False _ (Character 'E') -> 
           noCmd <| { model | graph = 
              activeObj model |> objToNode 
              |> Maybe.andThen (\id -> 
                   Graph.getNode id modelGraph |> Maybe.map (\ n -> { id = id, label = n}))
              |> Maybe.map (GraphProof.selectExtremePath modelGraph 0)
              |> Maybe.withDefault [] 
              |> List.foldl (\ e -> Graph.updateEdge e (\n -> {n | selected = True})) 
s                  (GraphDefs.clearSelection modelGraph) } -}
        KeyChanged False _ (Character 'L') -> 
           noCmd <| selectLoop True model
        KeyChanged False _ (Character 'H') -> 
           noCmd <| selectLoop False model
        KeyChanged False _ (Character 'G') -> 
           generateProof False            
        KeyChanged False _ (Character 'T') -> 
           generateProof True
        KeyChanged False _ (Character 'S') ->        
           noCmd <|
             setActiveGraph model
             <| GraphDefs.selectSurroundingDiagram model.mousePos modelGraph
        KeyChanged False k (Character 'C') -> 
             noCmd <| Modes.CutHead.initialise model
        KeyChanged False k (Character 'c') -> 
            if k.ctrl then noCmd model -- we don't want to interfer with the copy event C-c
            else
            let ids = GraphDefs.selectedEdges modelGraph |> List.filter (.label >> GraphDefs.isNormal) 
                       |> List.map .id
            in
              noCmd <| if ids == [] then model else 
                {  model | mode = ColorMode ids} 
                -- , 
                --   graph = GraphDefs.clearSelection 
                --   <| GraphDefs.clearWeakSelection modelGraph }              
        KeyChanged False _ (Character 'n') -> 
           Modes.NewLine.initialise model
        KeyChanged False _ (Character 'v') -> 
               let cmd = case GraphDefs.selectedIncompleteDiagram modelGraph of 
                      Nothing -> 
                        case GraphDefs.selectedChain modelGraph of
                          NoClearOrientation -> 
                             alert "Not clear how to orient the equation (closing the chain should not overlap with other arrows)"
                          NoChain ->
                            case GraphDefs.getSelectedProofDiagram modelGraph of 
                              NoProofNode -> alert "Selected subdiagram or proof node not found." 
                              NoDiagram -> alert "No diagram found around node."
                              JustDiagram { proof, diagram } ->
                                applyProof <| 
                                  { script = proof, statement = 
                                      GraphProof.statementToString diagram
                                  }
                          JustChain (_, d) -> 
                                requestProof { statement = GraphProof.statementToString d,
                                                       script = "reflexivity." }
                      Just d ->
                         let gp = GraphDefs.toProofGraph modelGraph in
                         let proof = GraphProof.findProofOfDiagram gp (Graph.nodes gp) d 
                                    |> Maybe.withDefault ""
                         in
                        --  requestProofForChain (GraphProof.statementToString d)
                         requestProof { statement = (GraphProof.statementToString d),
                                              script = proof }
               in
                 (model, cmd)
        AppliedProof {statement, script} ->
          let failWith s = (model, alert s) in
          let registerProof graph diagram = 
                case Parser.run equalityParser statement of
                  Err _ -> failWith ("fail to parse " ++ statement)
                  Ok eqs ->
                    case Unification.unifyDiagram eqs diagram graph of
                      Err s -> failWith s
                      Ok finalg ->                
                          noCmd <| setSaveGraph model finalg
          in
          let registerAndCreateProof newGraph diagram =
                    let nodes =  Graph.nodes 
                                <| GraphDefs.selectedGraph 
                                    modelGraph 
                    in
                    let g_with_proof = GraphDefs.createValidProofAtBarycenter newGraph nodes script in
                    registerProof g_with_proof diagram
          in
          case GraphDefs.selectedIncompleteDiagram modelGraph of
            Nothing ->  case GraphDefs.selectedChain modelGraph of
                JustChain (newGraph, diagram) -> registerAndCreateProof newGraph diagram
                    
                NoClearOrientation -> failWith "No clear orientation of the proof."
                NoChain -> case GraphDefs.getSelectedProofDiagram modelGraph of
                  NoProofNode -> failWith "No proof node selected."
                  NoDiagram -> failWith "no diagram around selected proof node."
                  JustDiagram { diagram } -> 
                    let validGraph = 
                          case GraphDefs.selectedNode modelGraph of
                            Nothing -> modelGraph
                            Just n -> 
                              if isProofLabel n.label then 
                                Graph.updateNode n.id (\ l -> { l | isCoqValidated = True, 
                                                     label = GraphDefs.makeProofString script}) modelGraph
                              else modelGraph
                    in
                    registerProof validGraph diagram
            Just d -> registerAndCreateProof modelGraph d
        KeyChanged False _ (Character 'q') -> 
            (model, promptFindReplace ())
        KeyChanged False _ (Character 'Q') -> 
            (model, quicksaveGraph 
            { info = toJsGraphInfo model, 
              export = makeExports model,             
              autosave = False })
        KeyChanged False _ (Character 'R') -> 
            noCmd <| initialise_Resize model
        KeyChanged False _ (Character 'r') -> rename model
        KeyChanged False _ (Character 's') -> 
            Modes.Square.initialise model 
        KeyChanged False _ (Character 't') -> createPoint False ""
        KeyChanged False _ (Character 'p') -> createPoint True ""
        -- KeyChanged False _ (Character 'P') -> createPoint True <| "\\" ++ coqProofTexCommand ++ "{}" 
           --noCmd <| { model | mode = NewNode }
        --   KeyChanged False _ (Character 'q') -> ({ model | mode = QuickInputMode Nothing },
        --                                            Msg.focusId quickInputId)

        
        KeyChanged False _ (Character '/') -> Modes.SplitArrow.initialise model
        KeyChanged False _ (Character 'x') ->
            noCmd <| setSaveGraph model <| GraphDefs.removeSelected modelGraph
        KeyChanged False _ (Character 'X') ->
            let latex = graphToTikz (getActiveSizeGrid model)
                            (GraphDefs.selectedGraph modelGraph)
            in
            let cmd = if latex == "" then
                         alert "No diagram found!"
                      else
                         latexToClipboard latex
            in
              (model, cmd)
            -- fillBottom latex "No diagram found!"
        KeyChanged False _ (Character 'V') ->
            let s = GraphDefs.selectedGraph modelGraph |> svgExport model in
            (model, generateSvg s)          
        KeyChanged False _ (Control "Delete") ->
            noCmd <| setSaveGraph model <| GraphDefs.removeSelected modelGraph            
        {- NodeClick n e ->
            
            let _ = Debug.log "nodeclick" () in
            noCmd <| addOrSetSel e.keys.shift n model -}
        EltDoubleClick n e ->
            noCmd <| initialise_RenameMode True [n] model
        {- EdgeClick n e ->
            let _ = Debug.log "edgeclick" () in
             noCmd <| addOrSetSel e.keys.shift n model  -}
        KeyChanged False _ (Character 'f') -> noCmd
            <| let isSel = GraphDefs.fieldSelect modelGraph  in
                case GraphDefs.selectedNodes modelGraph of
                 [] -> model
                 _ -> setSaveGraph model 
                       <| 
                        Graph.map 
                         (\ _ n -> if isSel n then GraphDefs.snapNodeToGrid sizeGrid n else n )
                        (always identity) modelGraph 
              
        KeyChanged False _ (Character 'h') -> move pi
        KeyChanged False _ (Character 'j') -> move (pi/2)
        KeyChanged False _ (Character 'k') -> move (3 * pi / 2)
        KeyChanged False _ (Character 'l') -> move 0       
        PasteGraph gi ->
          if not model.mouseOnCanvas then noCmd model else
         -- we ignore the other tabs
          case List.Extra.find .active gi.tabs of
              Nothing -> noCmd model
              Just tab ->
                   noCmd <| Modes.Move.initialise False FreeMove
                   <|  setSaveGraph model <| .extendedGraph <|          
                    Graph.disjointUnion 
                      (GraphDefs.clearSelection modelGraph)
                      (GraphDefs.selectAll tab.graph)
        KeyChanged False _ (Character 'u') ->
             let f = GraphDefs.fieldSelect modelGraph in
             let connectedGraph =  Graph.connectedClosure f f modelGraph in
             let isIncomplete = Graph.any (\ {n , isIn} -> f n /= isIn)
                                          (\ {e , isIn} -> f e /= isIn)
                                          connectedGraph
             in
             let newGraph = 
                    if isIncomplete then 
                       connectedGraph
                           |> Graph.map (\ _ {n , isIn} -> {n | selected = isIn})
                                        (\ _ {e , isIn} -> {e | selected = isIn})
                    else
                    -- adding proof nodes
                     
                     let selectedGraph = GraphDefs.selectedGraph modelGraph in
                     let isIn p = GraphDefs.getSurroundingDiagrams p selectedGraph /= [] in
                     let proofNodes = GraphDefs.getProofNodes modelGraph 
                          |> List.filter (.label >> .pos >> isIn)
                          |> List.map (Graph.nodeMap (\n -> { n | selected = True}))
                     in
                     Graph.updateNodes proofNodes modelGraph
             in
              noCmd <| setActiveGraph model newGraph
             
               
        KeyChanged False k (Character 'z') -> 
             if k.ctrl then noCmd <| undo model else noCmd model
        -- KeyChanged False _ (Character 'n') -> noCmd <| createModel defaultGridSize <| Graph.normalise modelGraph
        KeyChanged False k (Character '+') -> increaseZBy 1
        KeyChanged False k (Character '<') -> increaseZBy (-1)
        KeyChanged False _ k -> noCmd <|
           case GraphDefs.updateStyleEdges 
                  (ArrowStyle.keyMaybeUpdateStyle k)
                  (GraphDefs.selectedEdges modelGraph)
                  modelGraph of 
                 Nothing -> model
                 Just g -> setSaveGraph model g
        _ -> noCmd model              

svgExport : Model -> Graph NodeLabel EdgeLabel -> String
svgExport model graph = 
   let g = graph
                   |> GraphDefs.clearSelection 
                   |> GraphDefs.clearWeakSelection 
   in
   let box = GraphDefs.rectEnveloppe g |> Geometry.posDimsFromRect 
                      |> Geometry.pad (toFloat (getActiveSizeGrid model) / 2)
                      |> Geometry.rectFromPosDims
   in
            (Drawing.toString  
              [String.Svg.viewBox box]
              (g |> 
               GraphDrawing.toDrawingGraph |>
              toDrawing model))


coqExport : Model -> Graph NodeLabel EdgeLabel -> String
coqExport model graph = 
   let s = generateProofString False graph in
     if s == "" then "(* No diagram found *)" else s

selectByClick : Model -> Model
selectByClick model =
    if model.mouseOnCanvas then           
       updateActiveGraph model <| (\ modelGraph ->
              GraphDefs.addWeaklySelected <|
                      if model.specialKeys.shift then 
                        modelGraph 
                      else
                       GraphDefs.clearSelection modelGraph )
    else
            model


initialise_Resize : Model -> Model
initialise_Resize model =
         { model | mode = 
                       ResizeMode { sizeGrid = getActiveSizeGrid model,
                                    onlyGrid = False
                                  }
                     }             

initialiseEnlarge : Model -> Model
initialiseEnlarge model =
   { model | mode = EnlargeMode 
             {orig = model.mousePos,
             -- onlySubdiag = True,
              pos = InputPosMouse,
              direction = Free
       }
   }

update_DebugMode : Msg -> Model -> (Model, Cmd Msg)
update_DebugMode msg model =
    case msg of
        KeyChanged False _ (Control "Escape") -> switch_Default model
        _ -> noCmd model





update_Resize : ResizeState -> Msg -> Model -> (Model, Cmd Msg)
update_Resize st msg m =
  let finalise () = 
        let m2 = pushHistory m in
         noCmd <|
          setActiveGraph (setActiveSizeGrid { m2 | mode = DefaultMode } st.sizeGrid)
          <| graphResize st m
         -- computeLayout())
  in
  -- let _ = Debug.log "msg resize" msg in
  let increment = 10 in
  let newState st2 = 
       noCmd {m | mode = ResizeMode st2 }
  in
  let newSize si =
       let s = max minSizeGrid <| min maxSizeGrid si in
       newState { st | sizeGrid = s}       
  in
  case msg of
        KeyChanged False _ (Character '?') -> noCmd <| toggleHelpOverlay m
        KeyChanged False _ (Control "Escape") -> ({ m | mode = DefaultMode}, Cmd.none)
        KeyChanged False _ (Control "Enter") -> finalise ()
        -- MouseClick -> finalise ()        
        KeyChanged False _ (Character 'k') -> newSize (st.sizeGrid + increment)
        KeyChanged False _ (Character 'j') -> newSize (st.sizeGrid - increment)
        KeyChanged False _ (Character 'g') -> newState { st | onlyGrid = not st.onlyGrid}
        SizeGrid s -> newSize s
        _ -> noCmd m


-- functions that turns a model graph into one with more information
-- about the display, based on the mode


selectGraph : Model -> Point -> Bool -> Graph NodeLabel EdgeLabel
selectGraph m orig keep =
   let modelGraph = getActiveGraph m in
   let selRect = (Geometry.makeRect orig m.mousePos) in
   let g = if keep then modelGraph else GraphDefs.clearSelection modelGraph in
   let isSel n = Geometry.isInRect selRect n.pos in
   GraphDefs.addNodesSelection g isSel
   
enlargeGraph : Model -> EnlargeState -> Graph NodeLabel EdgeLabel
enlargeGraph m state =
   let modelGraph = getActiveGraph m in
   let sizeGrid = getActiveSizeGrid m in
   let (ox, oy) = case state.pos of      
          InputPosKeyboard p -> InputPosition.deltaKeyboardPos sizeGrid p
          _ -> 
            let (dx, dy) = Point.subtract m.mousePos state.orig in
              case state.direction of
                      Free -> (dx, dy)
                      Vertical -> (0, dy)
                      Horizontal -> (dx, 0)
   in   
   let diags = GraphDefs.getSurroundingDiagrams state.orig modelGraph in
   let edgesId = List.concatMap (GraphProof.edgesOfDiag >> IntDict.keys) diags
   in
   let gcon = 
          Graph.map (\ _ _ -> False) (\ _ _ -> False) modelGraph
          |> Graph.updateList edgesId (always True) (always True)
          |> Graph.connectedClosure identity identity
   in
   let noSurround = not (Graph.any .isIn .isIn gcon) in

   let (xi, yi) = state.orig in
   let mkp id n i o = 
        if n >= i && 
            (noSurround || (Graph.get id .isIn .isIn gcon
            |> Maybe.withDefault False))
                  then n + o else n 
   in
    
   let mapNode id n =
        let (nx, ny) = n.pos in        
          { n | pos = (mkp id nx xi ox, mkp id ny yi oy)}
         
   in
       
   let g = Graph.map 
            mapNode
            (always identity)
            modelGraph
   in
   g

{- enlargeGraph : Model -> Maybe Point -> Graph NodeLabel EdgeLabel
enlargeGraph m orig = 
  orig |> Maybe.map (enlargeGraphSel m) |> Maybe.withDefault modelGraph
 -}
graphDrawingFromModel : Model -> Graph NodeDrawingLabel EdgeDrawingLabel
graphDrawingFromModel m =
    let modelGraph = getActiveGraph m in
    case m.mode of
        ColorMode _ -> collageGraphFromGraph m modelGraph
        DefaultMode -> collageGraphFromGraph m modelGraph
        RectSelect p -> GraphDrawing.toDrawingGraph  <| selectGraph m p m.specialKeys.shift
        EnlargeMode p ->
             enlargeGraph m p
             |> collageGraphFromGraph m
--        NewNode -> collageGraphFromGraph m modelGraph
        Move s -> Modes.Move.graphDrawing m s          
        RenameMode _ l ->
            let g = graph_RenameMode l m in
            let g2 = collageGraphFromGraph m g in
            case l of
                (id, _) :: _ ->
                    Graph.update id 
                    (\n -> {n | editable = True })
                    (GraphDrawing.mapNormalEdge
                     <| \e ->  {e | editable = True })
                    g2
                _ -> g2
              
        DebugMode ->
            modelGraph |> collageGraphFromGraph m 
                |> Graph.map
                   (\id n ->  {n | label = String.fromInt id}) 
                   (\_ -> identity)
        NewLine astate -> Modes.NewLine.graphDrawing m astate  
        NewArrow astate -> Modes.NewArrow.graphDrawing m astate
        SquareMode state -> Modes.Square.graphDrawing m state
        SplitArrow state -> Modes.SplitArrow.graphDrawing m state
        PullshoutMode state -> Modes.Pullshout.graphDrawing m state
        CutHead state -> Modes.CutHead.graphDrawing m state
        ResizeMode sizeGrid -> graphResize sizeGrid m |> GraphDrawing.toDrawingGraph
        




-- tabResize : ResizeState -> Tab -> Tab
-- tabResize st tab =
--    if st.onlyGrid then tab else
--    let ratio = toFloat st.sizeGrid / toFloat tab.sizeGrid in
--    Graph.map (\_ n -> { n | pos = Point.resize ratio n.pos}) 
--       (\_ -> identity)
--     tab.graph

graphResize : ResizeState -> Model -> Graph NodeLabel EdgeLabel
graphResize st m =   
   let modelGraph = getActiveGraph m in
   let sizeGrid = getActiveSizeGrid m in
   if st.onlyGrid then modelGraph else
   let ratio = toFloat st.sizeGrid / toFloat sizeGrid in
   Graph.map (\_ n -> { n | pos = Point.resize ratio n.pos}) 
      (\_ -> identity)
    modelGraph
   


graphDrawingChain : Int -> Graph NodeLabel EdgeLabel -> QuickInput.Equation -> Graph NodeLabel EdgeLabel
graphDrawingChain offset g eq =         
            let mid = toFloat offset / 2 in
            let iniP = (mid, mid) in
            {- graphDrawingEquation -}
            QuickInput.graphEquation iniP (toFloat offset) 
               eq g  -- QuickInput.Right



type HelpStrType = Bold | Plain
helpMsgParser_aux : Parser (String, HelpStrType)
helpMsgParser_aux =
    
    let varParser cend = 
          let correctChar = \ c -> c /= cend in
          Parser.variable { start = correctChar, inner = correctChar, reserved = Set.empty }
    in
    Parser.oneOf [
         Parser.succeed (\ s -> (s , Bold))
             |. Parser.token "["
             |= Parser.oneOf [
               Parser.succeed identity 
               |. Parser.token "\""
               |= varParser '\"'
               |. Parser.token "\""
               ,
              varParser ']']
             |. Parser.symbol "]" ,
         Parser.succeed (\ s -> (s , Plain))
             |= varParser '['
        ]

helpMsgParser : Parser (List (String, HelpStrType))
helpMsgParser =
    Parser.succeed identity
        |= Parser.oneOf [
            Parser.succeed [] |. Parser.end,
            Parser.succeed (::) |= helpMsgParser_aux |= Parser.lazy (\_ -> helpMsgParser)
           ]

helpStr_collage : (String, HelpStrType) -> Html msg
helpStr_collage (s , h) =
    case h of
        Bold -> Html.span [] [Html.text "[", Html.b [] [Html.text s], Html.text"]"]
        Plain -> String.lines s |> List.map Html.text
                           |> List.intersperse (Html.br [] [])
                           |> Html.span []
        



overlayHelpMsgNewLine : String
overlayHelpMsgNewLine = HtmlDefs.overlayHelpMsg ++ ".\n"

helpMsg : Model -> Html Msg
helpMsg model =
    let classes = ["help-div"] in
    let cl = List.map Html.Attributes.class classes in
    let makeHelpDiv l = Html.div cl [Html.div [] l] in
    let msg = \ s -> s |>
                  Parser.run helpMsgParser |>
                  Result.withDefault [("Parsing help msg error", Plain)] |>
                  List.map helpStr_collage |> makeHelpDiv
    in
    -- let b = \ s -> Html.span [] [Html.text "[", Html.b [] [Html.text s], Html.text"]"]
    -- in
    -- let info = \ s1 s2 -> Html.span [] (b s1) (Html.text s2)
    case model.mode of
        DefaultMode ->
            -- msg <| "Default mode. couc[c]" 
            msg <| "Default mode.\n "
                ++ "Sumary of commands:\n"
                ++ overlayHelpMsgNewLine

                ++ "Selection:"
                ++ "  [click] for point/edge selection (hold for selection rectangle)"
                ++ ", [shift] to keep previous selection" 
                ++ ", [C-a] select all" 
                ++ ", [S]elect pointer surrounding subdiagram"
                ++ ", [u] expand selection to connected components"
                ++ " ([u] again to select embedded proof nodes)"
                ++ ", [ESC] or [w] clear selection"    
                ++ ", [H] and [L]: select subdiagram adjacent to selected edge"             
                ++ ", [hjkl] move the selection from a point to another"

                ++ "\nHistory: "
                ++ "[C-z] undo" 
                ++ ", [Q]uicksave" 
                ++ "\nCopy/Paste: "
                ++ "[C-c] copy selection" 
                ++ ", [C-v] paste"                

                ++ "\n Basic editing: "
                ++ "new [p]oint"
                -- ++ ", new [P]roof node"
                ++ ", new [t]ext"               
                ++ ", [del]ete selected object (also [x])"               
                ++ ", [q] find and replace in selection"                 
                ++ ", [r]ename selected object (or double click)" 
                ++ ", new (commutative) [s]quare on selected point (with two already connected edges)"

                ++ "\nArrows: "
                ++ "new [a]rrow/cylinder/cone from selected objects"                
                ++ ", new li[n]e"  
                ++ ", [/] split arrow" 
                ++ ", [C]ut head of selected arrow" 
                ++ ", [c]olor arrow" 
                ++ ", if an arrow is selected: [\""
                ++ ArrowStyle.controlChars
                ++ "\"] alternate between different arrow styles, [i]nvert arrow, "
                ++ "[+<] move to the foreground/background (also for vertices)."

                ++ "\nMoving objects:"
                ++ "[g] move selected objects with possible merge (hold g for "
                ++ "stopping the move on releasing the key)"
                ++ ", [f]ix (snap) selected objects on the grid" 
                ++ ", [e]nlarge diagram (create row/column spaces)"                 


                
                
                           
                
                 

                
                
                
                
                
                ++ "\n\nMiscelleanous: "
                ++ "[R]esize canvas and grid size" 
                ++ ", [d]ebug mode"                 
                ++ ", [G]enerate Coq script ([T]: generate test Coq script)"
                ++ ", [v] if a proof node is selected, check the proof, if a chain of arrows is selected, ask for a proof, if a subdiagram is selected, generate a proof goal in vscode."
                ++ " (only works with the coreact-yade vscode extension)"
                ++ ", [E] enter an equation (prompt)"
                ++ ", export selection to LaTe[X]/s[V]g"
                
                   --  ++ ", [q]ickInput mode" 
                
                
                   
                      -- b "b",
                      -- Html.text "litz flag (no labelling on point creation)."
             -- "[r]ename selected object, move selected point [g], [d]ebug mode"
        DebugMode ->
            "Debug Mode. [ESC] to cancel and come back to the default mode. " ++ 
             "" |> Html.text 
              --  Debug.toString model |> Html.text |> List.singleton |> makeHelpDiv
            {- QuickInputMode ch ->
            makeHelpDiv [
            "Mode: QuickInput" ++ Debug.toString model.mode ++ "." |> Html.text,
                Html.p [] [
                     msg <| " Syntax: v1 -> v2 - edgeLabel >@d v3 vr |down arrow v X | \"uparrow \" ^ end yo."
                    ++ " [RET] to accept the current chain"       
                    ++ ", [ESC] to cancel and comeback to the default mode."]
                ] -}
        NewArrow _ -> "Mode NewArrow. "
                          -- ++ Debug.toString model 
                           ++  Modes.NewArrow.help |> msg
        NewLine _ -> "Mode NewLine. "
                           ++  Modes.NewLine.help |> msg
        PullshoutMode _ -> "Mode Pullback/Pullshout. "
                          -- ++ Debug.toString model 
                           ++  Modes.Pullshout.help |> msg
        ColorMode _ -> "Mode color. "
                        ++ overlayHelpMsgNewLine
                        ++ "[ESC] or colorise selected edges: " ++ Color.helpMsg |> msg
        SquareMode _ -> "Mode Commutative square. "
                             ++ Modes.Square.help |> msg
        SplitArrow _ -> "Mode Split Arrow. "
                             ++ Modes.SplitArrow.help |> msg
        Move s -> Modes.Move.help s |> msg
        CutHead _ -> "Mode cut arrow. "
                 ++ Modes.CutHead.help
                  |> msg
        RenameMode _ _ -> msg "Rename mode: [RET] to confirm, [TAB] to next label, [ESC] to cancel"
        EnlargeMode s -> msg <| "Enlarge mode. "
                            ++ overlayHelpMsgNewLine
                            ++ "Draw a rectangle to create space. "
                            ++ "Use mouse or h,j,k,l. [RET] or click to confirm."
                            ++ " Press [x] or [y] to restrict to horizontal / vertical directions, or let it [f]ree." 
                         {-    ++ (if s.onlySubdiag then
                                    "Only extending surrounding subdiagram"
                               else
                                    "Moving all right and bottom vertices") -}
                            -- ++ " (press [s] to toggle)."
        ResizeMode { onlyGrid } -> msg <| "Resize mode. "
                         ++ overlayHelpMsgNewLine
                         ++ "[k]/[j] to increase/decrease, "
                         ++ "or use the slider above. "
                         ++ 
                         if onlyGrid then 
                         "[g] to resize the objects as well as the grid. "
                         else 
                         "[g] to resize the grid only. "
                         ++ "[ESC] to cancel, "
                         ++ "[RET] to confirm"

        _ -> let txt = "Mode: " ++ Modes.toString model.mode ++ ". [ESC] to cancel and come back to the default"
                   ++ " mode."
             in
                makeHelpDiv [ Html.text txt ]

additionnalDrawing : Model -> Drawing Msg
additionnalDrawing m =
   let drawSelPoint pointPos orig =
         Drawing.rect foregroundZ <| Geometry.makeRect orig
            <| Point.add (1,1) -- to make the rectangle appear even if one dim is empty
            <| pointPos
   in
   let drawSel pos orig = 
            case pos of
              InputPosKeyboard p ->
                   drawSelPoint 
                      (Point.add orig <| InputPosition.deltaKeyboardPos 
                      (getActiveSizeGrid m) p) orig
              _ -> drawSelPoint m.mousePos orig
   in
   case m.mode of
      RectSelect orig -> drawSel InputPosMouse orig
      EnlargeMode state -> 
         case (state.pos, state.direction) of
              (InputPosMouse, Vertical) -> 
                  drawSelPoint (first state.orig, second m.mousePos) state.orig
              (InputPosMouse, Horizontal) ->
                  drawSelPoint (first m.mousePos, second state.orig) state.orig
              _ -> drawSel state.pos state.orig
        
      _ -> --GraphDrawing.make_input (100.0,100.0) "coucou" (always Msg.noOp)
          Drawing.empty

view : Model -> Html Msg
view m =
   case m.scenario of
       SimpleScenario -> Html.div [] [Html.text m.statusMsg]
       _ -> viewGraph m

toDrawing : Model -> Graph NodeDrawingLabel EdgeDrawingLabel -> Drawing Msg
toDrawing model graph = 
    let cfg = { latexPreamble = case model.scenario of
                                   Exercise1 -> 
                                       "\\newcommand{\\depthHistory}{"
                                       ++ String.fromInt (List.length model.history)
                                       ++ "}"                                       
                                   _ -> model.latexPreamble 
              } 
    in
    graphDrawing cfg graph

renderTabs : List Tab -> List (Html Msg)
renderTabs tabs =
  let activeTab = getActiveTabInTabs tabs in
  let leftButton = Html.button [Html.Events.onClick TabMoveLeft, Html.Attributes.title "Swap tab order"] [Html.text "<"] in
  let rightButton = Html.button [Html.Events.onClick TabMoveRight, Html.Attributes.title "Swap tab order"] [Html.text ">"] in
  let renderTab i tab =
        
         let classes = 
                Html.Attributes.class "tab-button" :: 
                if tab.active then [Html.Attributes.class "active-tab"] else []
         in
         let mainButton = 
                Html.button ([(Html.Events.onClick <| SwitchTab i)
                    ] ++ classes) 
                [Html.text tab.title]
         in
           mainButton
  in
  let newButton = Html.button [Html.Events.onClick NewTab] [Html.text "New tab"] in
  let dupButton = Html.button [Html.Events.onClick DuplicateTab] [Html.text "Duplicate tab"] in
  let removeButton = Html.button [Html.Events.onClick RemoveTab] [Html.text "Remove tab"] in
  
  let renameButton = Html.button [Html.Events.onClick (Do (promptTabTitle activeTab.title))] [Html.text "Rename tab"] in
     [newButton, dupButton, removeButton, renameButton ] ++ List.indexedMap renderTab tabs
     ++ [leftButton, rightButton]

viewGraph : Model -> Html Msg
viewGraph model =
    let modelGraph = getActiveGraph model in
    let missings = Graph.invalidEdges modelGraph in   
    let drawings = toDrawing model (graphDrawingFromModel model) in
    let grid = if model.hideGrid then Drawing.empty else Drawing.grid (Model.getCurrentSizeGrid model) in
    let ruler = if not model.rulerShow then Drawing.empty else Drawing.ruler model.rulerMargin in
    let nmissings = List.length missings in
    let svg =   Drawing.group [grid,
                 drawings,
                 additionnalDrawing model,
                 ruler,
                 -- This is to prevent unwanted scrolling
                 -- that happened in chrome when editing the graph
                 -- I don't know why this was happening, neither why
                 -- this trick fixes the issue.                 
                 -- The problem only happened with foreignObject (svg.text 
                 -- was fine)
                 Drawing.emptyForeign
              ]
              -- |> debug
              |> Drawing.svg [
                          --   Html.Attributes.style "width" "4000px",
                          --   Html.Attributes.height 4000,
                             Html.Attributes.id HtmlDefs.canvasId,
                             Html.Attributes.style "border-style" "solid",
                             Html.Events.on "mousemove"
                               (D.map2 MouseMoveRaw D.value HtmlDefs.keysDecoder),
                             Html.Events.onMouseLeave MouseLeaveCanvas                               
                            ,                 
                           MouseEvents.onWithOptions "mousedown" 
                            { stopPropagation = False, preventDefault = False }
                            MouseDown
                            -- MouseEvents.onDown MouseDown
                     , Html.Events.onMouseUp MouseUp
                   --  , Html.Events.on "copy" (D.succeed CopyGraph)
                          --    , Msg.onTabAttribute
                       ]
    in
    let helpDiv = helpMsg model in
    let overlayHelp = 
           if model.showOverlayHelp then
             [ Html.div [Html.Attributes.class "overlay"] [helpDiv]]
           else []
    in
    let contents = 
          [ Html.div [] 
            (HtmlDefs.introHtml
            ++
            if model.scenario /= Watch then [
            Html.button [Html.Events.onClick (openFile () |> Do),
               Html.Attributes.id "load-button"] [Html.text "Load graph"] 
            ,  Html.button [Html.Events.onClick (quickLoad () |> Do),
               Html.Attributes.title "Local or session storage"] [Html.text "QuickLoad graph"]
            -- Button to open a directory     
            , Html.button [Html.Events.onClick (openDirectory () |> Do),
               Html.Attributes.title "Open a directory"] [Html.text "Open directory"]
            ]
            else []
            ),
            Html.text model.statusMsg,
            -- if model.unnamedFlag then Html.p [] [Html.text "Unnamed flag On"] else Html.text "",
            -- if state.blitzFlag then Html.p [] [Html.text "Blitz flag"] else Html.text "",
            Html.p [] 
            ([ helpMsg model
            ] ++ overlayHelp)
          ] ++
          [
             Html.button [Html.Events.onClick Save, Html.Attributes.id "save-button", 
               Html.Attributes.title "Opens a save dialog box"] 
               [Html.text "Save"]
           , Html.button [Html.Events.onClick (Clear {scenario = model.scenario, preamble = ""})] [Html.text "Clear"]
           
           
           , Html.a [Html.Attributes.href  ("#" ++ HtmlDefs.latexPreambleId)] [Html.text "Latex preamble"]
            {- , Html.button [Html.Events.onClick (Do <| computeLayout ()),
                   Html.Attributes.title "Should not be necessary"
            ] [Html.text "Recompute labels"] -}
           --  , Html.button [Html.Events.onClick FindInitial] [Html.text "Initial"]
           , HtmlDefs.checkbox ToggleHideGrid "Show grid" "" (not model.hideGrid)           
           , HtmlDefs.checkbox ToggleHideRuler "Show ruler" "" model.rulerShow           
           , HtmlDefs.checkbox ToggleAutosave "Autosave" "Quicksave every minute" (model.autoSave)
           , Html.button [Html.Events.onClick ExportQuiver] [Html.text "Export selection to quiver"] 
           , Html.button [Html.Events.onClick SaveRulerGridSize] [Html.text "Save ruler & grid size preferences"] 
           , Html.button [Html.Events.onClick OptimalGridSize, 
              Html.Attributes.title "Select two nodes. The new grid size is the max of the coordinate differences."] 
              [Html.text "Calibrate grid size"] 
           ]
          ++ 
          (if not model.rulerShow then [] else 
            [ HtmlDefs.slider RulerMargin 
           ("Ruler margin (" ++ String.fromInt model.rulerMargin ++ ")")
                  minRulerMargin maxRulerMargin model.rulerMargin ]
          )
          ++
           (if isResizeMode model.mode then
               [ HtmlDefs.slider SizeGrid 
                ("Grid size (" ++ String.fromInt (Model.getCurrentSizeGrid model) ++ ")")
                  minSizeGrid maxSizeGrid (Model.getCurrentSizeGrid model) ]
            else
               [])
          ++ 
          [ Html.p [Html.Attributes.class "tabs"] (renderTabs model.tabs),          
            Html.p [] [ Html.text <| if nmissings > 0 then 
               String.fromInt nmissings ++ " nodes or edges could not be rendered."
               else "" ]
           , svg
           , Html.p [] [
            Html.text "LaTeX preamble",
            Html.textarea [Html.Attributes.cols 100, Html.Attributes.rows 100, 
              Html.Attributes.placeholder "latex Preamble",
              Html.Attributes.value model.latexPreamble, 
              Html.Attributes.id HtmlDefs.latexPreambleId,
              Html.Events.onInput LatexPreambleEdit
            ] [ ]
           ]
          ]
    in
    Html.div [] contents



main : Program {defaultGridSize : Int, rulerMargin : Int} Model Msg
main = Browser.element { init = \ {defaultGridSize, rulerMargin} -> (createModel defaultGridSize rulerMargin, Cmd.none),
                         view = view, update = updateIntercept,
                         subscriptions = subscriptions}
