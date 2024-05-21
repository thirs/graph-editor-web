module GraphDefs exposing (EdgeLabel, NodeLabel,
   NormalEdgeLabel, EdgeType(..), GenericEdge, edgeToNodeLabel,
   filterLabelNormal, filterEdgeNormal, isNormalId, isNormal, isPullshout,
   filterNormalEdges, coqProofTexCommand,
   newNodeLabel, newEdgeLabel, newPullshout, emptyEdge,
   selectedEdges, mapNormalEdge,  mapDetails, 
   createNodeLabel, createProofNode,
   getNodeLabelOrCreate, getNodeDims, getNodePos, getEdgeDims,
   addNodesSelection, selectAll, clearSelection, 
   clearWeakSelection,
   selectedGraph,
   fieldSelect,
   selectedNodes,
   isEmptySelection,
   selectedEdge,
   selectedEdgeId, selectedNode, selectedId,
   removeSelected, getLabelLabel, getProofNodes,
   getNodesAt, snapToGrid, snapNodeToGrid, exportQuiver,
   addOrSetSel, toProofGraph, selectedIncompleteDiagram,
   selectSurroundingDiagram,
   centerOfNodes, mergeWithSameLoc,
   findReplaceInSelected, {- closestUnnamed, -} unselect, closest,
   makeSelection, addWeaklySelected, weaklySelect, weaklySelectMany,
   getSurroundingDiagrams, updateNormalEdge,
   rectEnveloppe, updateStyleEdges,
   getSelectedProofDiagram, MaybeProofDiagram(..), selectedChain, MaybeChain(..),
   createValidProofAtBarycenter, isProofLabel, makeProofString, posGraph
   )

import IntDict
import Zindex exposing (defaultZ)
import Geometry.Point as Point exposing (Point)
import Geometry exposing (LabelAlignment(..))
import Geometry.QuadraticBezier as Bez
import ArrowStyle exposing (ArrowStyle)
import Polygraph as Graph exposing (Graph, NodeId, EdgeId, Node, Edge)
import GraphProof exposing (LoopNode, LoopEdge, Diagram)

import Json.Encode as JEncode
import List.Extra as List
import Maybe.Extra as Maybe
import Geometry.Point
import Geometry.QuadraticBezier exposing (QuadraticBezier)

type alias NodeLabel = { pos : Point , label : String, dims : Maybe Point, 
                         selected : Bool, weaklySelected : Bool,
                         isMath : Bool, zindex: Int, isCoqValidated: Bool}

type alias EdgeLabel = GenericEdge EdgeType
type alias GenericEdge a = { details : a, selected : Bool,
                   weaklySelected : Bool,
                   zindex : Int}


type EdgeType = 
     PullshoutEdge
   | NormalEdge NormalEdgeLabel

type alias NormalEdgeLabel = { label : String, style : ArrowStyle, dims : Maybe Point}

coqProofTexCommand = "coqproof"

edgeToNodeLabel : Point -> EdgeLabel -> NodeLabel
edgeToNodeLabel pos l = 
   let nodeLabel = { pos = pos, label = "", dims = Nothing,
                 selected = l.selected, weaklySelected = l.weaklySelected,
                 zindex = l.zindex, isMath = True, isCoqValidated = False}
   in
   case l.details of 
     PullshoutEdge -> nodeLabel
     NormalEdge {label, dims} -> {nodeLabel | label = label, dims = dims}

filterNormalEdges : EdgeType -> Maybe NormalEdgeLabel
filterNormalEdges d =  case d of
             PullshoutEdge -> Nothing
             NormalEdge l -> Just l

filterLabelNormal : EdgeLabel -> Maybe (GenericEdge NormalEdgeLabel)
filterLabelNormal =
    mapDetails filterNormalEdges
             >> flattenDetails

filterEdgeNormal : Edge EdgeLabel -> Maybe (Edge (GenericEdge NormalEdgeLabel))
filterEdgeNormal e =
      filterLabelNormal e.label |>
                    Maybe.map (
                        \ l -> 
                        Graph.edgeMap (always l) e
                    )
       

keepNormalEdges : Graph NodeLabel EdgeLabel -> Graph NodeLabel (GenericEdge NormalEdgeLabel)
keepNormalEdges = Graph.filterMap Just
   filterLabelNormal

mapEdgeType : (NormalEdgeLabel -> NormalEdgeLabel) -> EdgeType -> EdgeType
mapEdgeType f e = case e of
    PullshoutEdge -> PullshoutEdge
    NormalEdge l -> NormalEdge (f l)

mapDetails : (a -> b) -> GenericEdge a -> GenericEdge b
mapDetails f e = 
    { weaklySelected = e.weaklySelected
    , selected = e.selected
    , details = f e.details
    , zindex = e.zindex}

isNormal : EdgeLabel -> Bool
isNormal = not << isPullshout

isPullshout : EdgeLabel -> Bool
isPullshout e = e.details == PullshoutEdge

isNormalId : Graph NodeLabel EdgeLabel -> Graph.Id -> Bool
isNormalId g id = Graph.get id (always True)
    isNormal g |> Maybe.withDefault False

mapNormalEdge : (NormalEdgeLabel -> NormalEdgeLabel) -> EdgeLabel -> EdgeLabel
mapNormalEdge = mapEdgeType >> mapDetails

flattenDetails : GenericEdge (Maybe a) -> Maybe (GenericEdge a)
flattenDetails e = 
   e.details |> Maybe.map
   (\d -> mapDetails (always d) e)

{-   
computeEdgePos : Point -> Point -> EdgeLabel -> Point
computeEdgePos from to e = e.style.bend
    let q = Geometry.segmentRectBent from to e.style.bend in
    if Bez.isLine q then
              Point.diamondPx q.from q.to offset
              
            else 
              let m = Bez.middle q in
              Point.add m <|
              Point.normalise offset <|        
               Point.subtract q.controlPoint <| m -}

getProofFromLabel : String -> Maybe String
getProofFromLabel s =
   let s2 = String.trim s in
   let prefix = "\\" ++ coqProofTexCommand ++ "{" in
   if String.startsWith prefix s2 then
      Just (String.slice (String.length prefix) (-1) s2)
   else
      Nothing

isProofLabel : NodeLabel -> Bool
isProofLabel l = getProofFromLabel l.label /= Nothing

getProofNodes : Graph NodeLabel EdgeLabel -> List (Node NodeLabel)
getProofNodes g =
   Graph.nodes g |> List.filter (\n -> isProofLabel n.label)


selectedProofNode : Graph NodeLabel EdgeLabel -> Maybe (Node NodeLabel, String)
selectedProofNode g =
  case selectedNode g |> Maybe.map 
     (\n -> (n, getProofFromLabel n.label.label)) of
      Nothing -> Nothing
      Just (_, Nothing) -> Nothing
      Just (n, Just s) -> Just (n, s)

type MaybeProofDiagram =
     NoProofNode
   | NoDiagram
   | JustDiagram { proof : String, diagram : Diagram}

-- returns the diagram around the selected proof
getSelectedProofDiagram : Graph NodeLabel EdgeLabel -> MaybeProofDiagram
getSelectedProofDiagram g =
  case selectedProofNode g of
    Nothing -> NoProofNode
    Just (n, s) ->
       case getSurroundingDiagrams n.label.pos g of 
         [] -> NoDiagram
         d :: _ -> JustDiagram { proof = s, diagram = d }


toProofGraph :  Graph NodeLabel EdgeLabel -> Graph LoopNode LoopEdge
toProofGraph = 
    keepNormalEdges >>
    Graph.removeLoops >>
    Graph.mapRecAll (\n -> n.pos)
             (\n -> n.pos)
             (\ _ n -> { pos = n.pos, label = n.label, proof = getProofFromLabel n.label })
             (\ _ fromP toP {details}  -> 
                        { angle = Point.subtract toP fromP |> Point.pointToAngle ,
                          label = details.label, -- (if l.label == "" && l.style.double then fromLabel else l.label),
                          pos = Point.middle fromP toP,
                          identity = details.style.double })

selectedIncompleteDiagram : Graph NodeLabel EdgeLabel -> Maybe Diagram
selectedIncompleteDiagram g = 
   let gc = (toProofGraph g) in
    GraphProof.getIncompleteDiagram gc
     <| Graph.getEdges (selectedEdges g |> List.map .id) gc

type MaybeChain =
     JustChain (Graph NodeLabel EdgeLabel, Diagram)
   | NoClearOrientation
   | NoChain
{-
Returns the graph with an edge added between the minimal and the maximal points, and the diagram
-}
selectedChain : Graph NodeLabel EdgeLabel -> MaybeChain
selectedChain g = 
   let gs = selectedGraph g in
   case (Graph.minimal gs, Graph.maximal gs) of
     ([ minId ] , [ maxId ]) ->
        if minId == maxId then NoChain else
        let (weakSel, trueSel) = if isTrueSelection gs then (False, True) else (True, False) in
        let label = { emptyEdge | weaklySelected = weakSel, selected = trueSel } in
        let (newGraph, _) = Graph.newEdge g minId maxId label in
        case selectedIncompleteDiagram newGraph of
          Nothing -> NoClearOrientation
          Just d -> JustChain (newGraph, d)
     (_, _) -> NoChain

updateNormalEdge : EdgeId -> (NormalEdgeLabel -> NormalEdgeLabel) -> Graph NodeLabel EdgeLabel -> Graph NodeLabel EdgeLabel
updateNormalEdge id f =
    Graph.updateEdge id 
     (mapNormalEdge f)

updateStyleEdges : (ArrowStyle -> Maybe ArrowStyle) 
        -> List (Edge EdgeLabel) -> Graph NodeLabel EdgeLabel -> Maybe (Graph NodeLabel EdgeLabel)
updateStyleEdges update edges g =
     let updateStyle e = update e.label.details.style 
                           |> Maybe.map (\newStyle ->
                              { id = e.id , style = newStyle }
                           )                    
     in
     let newEdges =  edges
                 |> List.filterMap filterEdgeNormal
                 |> List.filterMap updateStyle
     in
     let updateEdge edge graph =            
              updateNormalEdge edge.id 
              (\ e -> { e | style = edge.style})
              graph
     in
     if newEdges == [] then Nothing else
     let newGraph = List.foldl updateEdge g newEdges in
     Just newGraph


exportQuiver : Int -> Graph NodeLabel EdgeLabel -> JEncode.Value
exportQuiver sizeGrid g =
  let gnorm = g |> keepNormalEdges |> Graph.normalise in
  let nodes = Graph.nodes gnorm
      edges = Graph.edges gnorm
  in
  let coordInt x = floor (x / toFloat sizeGrid) |> JEncode.int in
  let encodePos (x, y) = [coordInt x, coordInt y] in
  let encodeNode n = JEncode.list identity <| encodePos n.label.pos ++ 
            [ JEncode.string (if n.label.label == "" then "\\bullet" else n.label.label)] in
  let encodeEdge e = JEncode.list identity <| 
               [JEncode.int e.from
               , JEncode.int e.to
               , JEncode.string e.label.details.label
               , JEncode.int (if e.label.details.style.labelAlignment == Right then 2 else 0) -- alignment
               , JEncode.object <| ArrowStyle.quiverStyle e.label.details.style
                  -- [("level", if e.label.style.double then JEncode.int 2 else JEncode.int 1)] --options
                ] in
  let jnodes = nodes |> List.map encodeNode
      jedges = edges |> List.map encodeEdge
  in
  JEncode.list identity <|
  [JEncode.int 0, JEncode.int <| List.length nodes] ++ jnodes ++ jedges

newNodeLabel : Point -> String -> Bool -> Int -> NodeLabel
newNodeLabel p s isMath zindex = 
    { pos = p , label = s, dims = Nothing, selected = False, weaklySelected = False,
                         isMath = isMath, zindex = zindex, isCoqValidated = False}

makeProofString : String -> String
makeProofString s = "\\" ++ coqProofTexCommand ++ "{" ++ s ++ "}"

newProofLabel : Point -> String -> NodeLabel
newProofLabel p s =
   newNodeLabel p (makeProofString s) True defaultZ

newGenericLabel : a -> GenericEdge a
newGenericLabel d = { details = d,
                      selected = False,
                      weaklySelected = False,
                      zindex = defaultZ}

newEdgeLabel : String -> ArrowStyle -> EdgeLabel
newEdgeLabel s style = newGenericLabel <| NormalEdge { label = s, style = style, dims = Nothing }

newPullshout : EdgeLabel
newPullshout = newGenericLabel PullshoutEdge


emptyEdge : EdgeLabel
emptyEdge = newEdgeLabel "" ArrowStyle.empty


createNodeLabel : Graph NodeLabel EdgeLabel -> String -> Point -> (Graph NodeLabel EdgeLabel,
                                                                       NodeId, Point)
createNodeLabel g s p =
    let label = newNodeLabel p s True defaultZ in
    let (g2, id) = Graph.newNode g label in
     (g2, id, p)

createProofNode : Graph NodeLabel EdgeLabel -> String -> Bool -> Point -> Graph NodeLabel EdgeLabel
createProofNode g s coqValidated p =
    let label = newProofLabel p s in
    let (g2, id) = Graph.newNode g { label | isCoqValidated = coqValidated } in
     g2

createValidProofAtBarycenter : Graph NodeLabel EdgeLabel -> List (Node NodeLabel) -> String -> Graph NodeLabel EdgeLabel
createValidProofAtBarycenter g nodes proof =
   let nodePositions = Debug.log "Node positions" <| List.map (.label >> .pos) <| nodes in
   createProofNode g proof True
          <| Geometry.Point.barycenter nodePositions

getNodeLabelOrCreate : Graph NodeLabel EdgeLabel -> String -> Point -> (Graph NodeLabel EdgeLabel,
                                                                       NodeId, Point)
getNodeLabelOrCreate g s p =
    if s == "" then
       createNodeLabel g s p
    else
        case Graph.filterNodes g (\ l -> l.label == s) of
            [] -> createNodeLabel g s p
            t :: _ -> (g , t.id, t.label.pos)


defaultDims : String -> Point
defaultDims s = 
  let height = 16 in
  let size = 1 in --max 1 (String.length s) in
   -- copied from source code of Collage
   (height / 2 * toFloat size, height)

getNodeDims : NodeLabel -> Point
getNodeDims n =
    case  n.dims of
        Nothing -> defaultDims n.label
        Just p -> p

getNodePos : NodeLabel -> Point
getNodePos n =
   if n.isMath then n.pos else
   Point.add n.pos (Point.resize 0.5 (getNodeDims n))
    
getEdgeDims : NormalEdgeLabel -> Point
getEdgeDims n =
    case  n.dims of
        Nothing -> defaultDims n.label
        Just p -> p

-- select nodes and everything between them
addNodesSelection : Graph NodeLabel EdgeLabel -> (NodeLabel -> Bool) -> Graph NodeLabel EdgeLabel
addNodesSelection g f =
      Graph.mapRecAll .selected
        .selected
       (\_ n -> { n | selected = f n || n.selected})
       (\_ s1 s2 e -> {e | selected = (s1 && s2) || e.selected })
       g
    -- Graph.map 
    --    (\_ n -> { n | selected = f n })(\_ -> identity) g

selectAll : Graph NodeLabel EdgeLabel -> Graph NodeLabel EdgeLabel
selectAll g = addNodesSelection g (always True)

isTrueSelection : Graph NodeLabel EdgeLabel -> Bool
isTrueSelection g = Graph.any .selected .selected g

fieldSelect : Graph NodeLabel EdgeLabel -> ({ a | selected : Bool, weaklySelected : Bool} -> Bool)
fieldSelect g = if isTrueSelection g then .selected else .weaklySelected

selectedGraph : Graph NodeLabel EdgeLabel -> Graph NodeLabel EdgeLabel
selectedGraph g = 
   let f = fieldSelect g in
   Graph.keepBelow f f g

selectedNodes : Graph NodeLabel EdgeLabel -> List (Node NodeLabel)
selectedNodes g = Graph.nodes g |> List.filter (.label >> fieldSelect g)

selectedEdges : Graph NodeLabel EdgeLabel -> List (Edge EdgeLabel)
selectedEdges g = Graph.edges g |> List.filter (.label >> fieldSelect g)

isEmptySelection : Graph NodeLabel EdgeLabel -> Bool
isEmptySelection go =
   not (Graph.any .selected .selected go) && 
   not (Graph.any .weaklySelected .weaklySelected go)

selectedNode : Graph NodeLabel EdgeLabel -> Maybe (Node NodeLabel)
selectedNode g = 
    case selectedNodes g of
       [ x ] -> Just x
       _ -> Nothing

selectedEdge : Graph NodeLabel EdgeLabel -> Maybe (Edge EdgeLabel)
selectedEdge g = 
    case selectedEdges g of
       [ x ] -> Just x
       _ -> Nothing

selectedEdgeId : Graph NodeLabel EdgeLabel -> Maybe EdgeId
selectedEdgeId = selectedEdge >> Maybe.map .id
    
selectedId : Graph NodeLabel EdgeLabel -> Maybe Graph.Id
selectedId g = 
   case (List.map .id <| selectedNodes g)
          ++ (List.map .id <| selectedEdges g) of
      [ x ] -> Just x
      _ -> Nothing


removeSelected : Graph NodeLabel EdgeLabel -> Graph NodeLabel EdgeLabel
removeSelected g = 
   let f = fieldSelect g in
   Graph.drop f f g

clearSelection : Graph NodeLabel EdgeLabel -> Graph NodeLabel EdgeLabel
clearSelection g =
  Graph.map (\_ n -> {n | selected = False})
            (\_ e -> {e | selected = False}) g

clearWeakSelection : Graph NodeLabel EdgeLabel -> Graph NodeLabel EdgeLabel
clearWeakSelection g =
  Graph.map (\_ n -> {n | weaklySelected = False})
            (\_ e -> {e | weaklySelected = False}) g


getNodesAt : Graph NodeLabel e -> Point -> List NodeId
getNodesAt g p =
  Graph.filterNodes g
    (\n -> Geometry.isInPosDims { pos = getNodePos n, 
                                  dims = getNodeDims n} p)
  |> List.map .id


snapNodeToGrid : Int -> NodeLabel -> NodeLabel
snapNodeToGrid sizeGrid n =  { n | pos = Point.snapToGrid (toFloat sizeGrid) n.pos }

snapToGrid : Int -> Graph NodeLabel EdgeLabel -> Graph NodeLabel EdgeLabel
snapToGrid sizeGrid g =
   Graph.map (\_ -> snapNodeToGrid sizeGrid) (\_ -> identity ) g

getLabelLabel : Graph.Id -> Graph NodeLabel EdgeLabel -> Maybe String
getLabelLabel id g = g |> Graph.get id (Just << .label) 
          (.details >> filterNormalEdges >> Maybe.map .label)
          |> Maybe.join

addOrSetSel : Bool -> Graph.Id -> Graph NodeLabel EdgeLabel -> Graph NodeLabel EdgeLabel
addOrSetSel keep o gi =

    let g = if keep then gi else clearSelection gi in
    let g2 = Graph.update o (\n -> {n | selected = True}) 
                  (\n -> {n | selected = True}) g
    in
       {-   = case o of
          ONothing -> g
          ONode id -> Graph.updateNode id (\n -> {n | selected = True}) g
          OEdge id -> Graph.updateEdge id (\n -> {n | selected = True}) g
    in -}
   g2

unselect : Graph.Id -> Graph NodeLabel EdgeLabel -> Graph NodeLabel EdgeLabel
unselect id = Graph.update id 
               (\ n -> { n | selected = False})
               (\ e -> { e | selected = False})

weaklySelect : Graph.Id -> Graph NodeLabel EdgeLabel -> Graph NodeLabel EdgeLabel
weaklySelect id = 
      weaklySelectMany [id]
weaklySelectMany : List Graph.Id -> Graph NodeLabel EdgeLabel -> Graph NodeLabel EdgeLabel
weaklySelectMany ids g =
   clearWeakSelection g 
   |> Graph.updateList ids  (\ n -> { n | weaklySelected = True})
               (\ e -> { e | weaklySelected = True}) 


selectEdges : Graph NodeLabel EdgeLabel -> List EdgeId -> Graph NodeLabel EdgeLabel
selectEdges = List.foldl (\ e -> Graph.updateEdge e (\n -> {n | selected = True}))

getSurroundingDiagrams : Point -> Graph NodeLabel EdgeLabel -> List Diagram
getSurroundingDiagrams pos gi =   
   let gp = toProofGraph gi in 
   GraphProof.getAllValidDiagrams gp 
            |> List.filter (GraphProof.isInDiag gp pos)
   

selectSurroundingDiagram : Point -> Graph NodeLabel EdgeLabel -> Graph NodeLabel EdgeLabel
selectSurroundingDiagram pos gi =   
   case getSurroundingDiagrams pos gi of
       [] -> gi
       d :: _ ->
          let edges = GraphProof.edgesOfDiag d |> IntDict.keys in
          selectEdges (clearSelection gi) edges

centerOfNodes : List (Node NodeLabel) -> Point
centerOfNodes nodes = ((Geometry.rectEnveloppe <| List.map (.pos << .label) nodes) |> Geometry.centerRect)

mergeWithSameLoc : Node NodeLabel -> Graph NodeLabel EdgeLabel -> Maybe (Graph NodeLabel EdgeLabel)
mergeWithSameLoc n g =
    case getNodesAt g n.label.pos |> List.filterNot ((==) n.id) of
         [ i ] -> Just (Graph.removeLoops <| Graph.recursiveMerge i n.id g)
         _ -> Nothing

findReplaceInSelected : Graph NodeLabel EdgeLabel -> {search : String, replace: String} ->  Graph NodeLabel EdgeLabel
findReplaceInSelected g r =
  let repl sel s = 
       if sel then
          String.replace r.search r.replace s
       else
          s
  in
  let f = fieldSelect g in
  Graph.map (\ _ n -> { n | label = repl (f n) n.label })
     (\_  e -> mapNormalEdge 
           (\ l -> { l |  label = repl (f e) l.label })
           e
           ) 
           
      g

distanceToNode : Point -> NodeLabel -> Float
distanceToNode p n = 
   let posDims = { pos = n.pos, dims = getNodeDims n } in
   let rect = Geometry.rectFromPosDims posDims in 
   Geometry.distanceToRect p rect

{- unnamedGraph : Graph NodeLabel EdgeLabel -> Graph NodeLabel EdgeLabel
unnamedGraph = 
   Graph.keepBelow (.label >> String.isEmpty)
     (.label >> String.isEmpty) -}

posGraph : Graph NodeLabel EdgeLabel -> 
   Graph NodeLabel
         {label : EdgeLabel, bezier : Maybe QuadraticBezier}
posGraph g = 
      let padding = 5 in
      let computeEdge _ n1 n2 e = 
            
             case e.details of
               PullshoutEdge -> 
                 {label = e, posDims = { pos = (0, 0), dims = (0, 0)}, bezier = Nothing}
               NormalEdge l ->
                   let q = Geometry.segmentRectBent n1 n2 l.style.bend in
                   {label = e, 
                    posDims = 
                         {
                             pos = Bez.middle q,
                             dims = (padding, padding) |> Point.resize 4
                         },
                     bezier = Just q}
            
      in
      Graph.mapRecAll     
              .posDims .posDims      
              (\id n -> { 
                      label = n,
                      posDims = {
                      dims =                       
                     --  if n.editable then (0, 0) else
                      -- copied from source code of Collage                         
                         getNodeDims n, 
                      pos = n.pos
                      } |> Geometry.pad padding
                       } )
                 computeEdge
              g
   |> Graph.map 
       (\_ {label} -> label) 
       (\_ {label, bezier } -> { bezier = bezier, label = label })

closest : Point -> Graph NodeLabel EdgeLabel -> Graph.Id
-- ordered by distance to Point
closest pos ug =
   
   case getNodesAt ug pos of
     t :: _ -> t
     _ -> 
        let edgeDistance e = 
             Maybe.map Bez.middle e.bezier |>
                        Maybe.map (Point.distance pos)
        in
        let ug2 = posGraph ug 
                 |> Graph.map 
                   (always <| distanceToNode pos)
                   (always edgeDistance)
        in
   
        let unnamedEdges = Graph.edges ug2 |> List.filterMap 
                           (\ {id, label} -> Maybe.map (\ l -> {id = id, label = l}) label)
            unnamedNodes = Graph.nodes ug2 
        in
        let unnamedAll = unnamedEdges ++ unnamedNodes 
               |> List.minimumBy .label 
               |> Maybe.map .id
               |> Maybe.withDefault 0
        in
         unnamedAll
{- 

closestUnnamed : Point -> Graph NodeLabel EdgeLabel -> List Graph.Id
-- ordered by distance to Point
closestUnnamed pos g = 
   let ug = unnamedGraph g in
   -- we need the pos
   let ug2 = Graph.mapRecAll .pos .pos 
         (\ _ n -> { empty = String.isEmpty n.label, pos = n.pos})
         (\ _ p1 p2 e -> { empty = String.isEmpty e.label, pos = Point.middle p1 p2})
         ug
   in
   let getEmptysDistance l = l
          |> List.filter (.label >> .empty)
          |> List.map (\ o -> 
                       {  id = o.id, 
                          distance = Point.distance o.label.pos pos})
          
   in
   let unnamedEdges = Graph.edges ug2 |> getEmptysDistance in
   let unnamedNodes = Graph.nodes ug2 |> getEmptysDistance in
   -- TODO: order them by distance to mousepos?
   let unnamedAll = unnamedEdges ++ unnamedNodes 
        |> List.sortBy .distance 
        |> List.map .id
   in
   unnamedAll -}

addWeaklySelected : Graph NodeLabel EdgeLabel -> Graph NodeLabel EdgeLabel
addWeaklySelected =
  Graph.map (\ _ n -> { n | selected = n.weaklySelected || n.selected})
     (\ _ n -> { n | selected = n.weaklySelected || n.selected})

makeSelection : Graph NodeLabel EdgeLabel -> Graph NodeLabel EdgeLabel
makeSelection g =
   if Graph.any .selected .selected g then
      g
   else
      addWeaklySelected g

rectEnveloppe : Graph NodeLabel EdgeLabel -> Geometry.Rect
rectEnveloppe g =
   let points = Graph.nodes g |> List.map (.label >> .pos) in
   Geometry.rectEnveloppe points