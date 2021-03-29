module Modes.Square exposing (help, graphDrawing, initialise, update)



-- import Graph exposing (..)

import Polygraph as Graph exposing (Graph, NodeId, EdgeId)
import Maybe exposing (withDefault)
import Msg exposing (Msg(..))
import HtmlDefs exposing (Key(..))
import GraphDefs exposing (NodeLabel, EdgeLabel)
import List.Extra exposing (uniquePairs, getAt)
import Modes exposing (SquareState, Mode(..))
import Model exposing (..)
import InputPosition exposing (InputPosition(..))
import ArrowStyle

import GraphDrawing exposing (NodeDrawingLabel, EdgeDrawingLabel)
import MyDiff



possibleSquareStates : Graph GraphDefs.NodeLabel GraphDefs.EdgeLabel -> Graph.NodeId {- NodeContext a b -} -> List SquareState
possibleSquareStates g id =
    let chosenLabel = Graph.get id .label .label g |> Maybe.withDefault "" in
    
    -- Boolean: is it going to the node?
    let
        ins = Graph.incomings id g
            -- IntDict.keys nc.incoming
             |> List.filterMap 
             (\x -> 
             Graph.get x.from .label .label g |>
             Maybe.map (\ labelNode -> 
             ( x, (labelNode, x.from), 
             True )))

        outs = Graph.outgoings id g
            -- IntDict.keys nc.outgoing 
            |> List.filterMap 
             (\x -> 
             Graph.get x.to .label .label g |>
             Maybe.map (\ labelNode -> 
             ( x, (labelNode, x.to), 
             False )))
    in
    ins
        ++ outs
        |> uniquePairs
        |> List.map
            (\( ( e1, (l1,n1), i1 ), ( e2, (l2,n2), i2 ) ) ->
                { chosenNode = id
                , chosenLabel = chosenLabel
                --   -- we don't care
                -- , movedNode = 0
                , n1 = n1
                , n2 = n2
                , e1 = e1
                , e2 = e2
                , n1ToChosen = i1
                , n2ToChosen = i2
                , configuration = 0
                , n1Label = l1
                , n2Label = l2                
                }
            )







square_setPossibility : Int -> Graph GraphDefs.NodeLabel GraphDefs.EdgeLabel -> NodeId -> Maybe SquareState
square_setPossibility idx g chosenNode =
    -- Graph.get chosenNode g
    --     |> Maybe.map 
    let possibilities = possibleSquareStates g chosenNode in
    possibilities 
                    |> getAt idx
                    |> Maybe.map
                        (\s ->
                            { s | configuration =                             
                                    (modBy (List.length possibilities) (idx + 1))
                            }
                        )
            


square_updatePossibility : Model -> Int -> NodeId -> ( Model, Cmd Msg )
square_updatePossibility m idx node =
    square_setPossibility idx m.graph node
        |> Maybe.map (\state -> { m | mode = SquareMode state })
        |> Maybe.withDefault m
        |> noCmd



-- second argument: the n-th possibility


initialise : Model -> ( Model, Cmd Msg )
initialise m =
    activeObj m
        |> objToNode
        |> Maybe.map (square_updatePossibility m 0)
        -- |> Maybe.map
        -- -- prevent bugs (if the mouse is thought
        -- -- to be kept on a point)
        --    (Tuple.mapFirst (\model -> { model | mousePointOver = ONothing}))
        |> Maybe.withDefault (noCmd m)






nextStep : Model -> Bool -> SquareState -> ( Model, Cmd Msg )
nextStep model finish state =
         
    let
        ( info, movedNode, created ) =
            moveNodeViewInfo model state
    in
    let m2 = addOrSetSel False (ONode movedNode) { model | graph = info.graph } in
     if finish then switch_Default m2 else
        let ids = 
                         if created then [ movedNode , info.edges.ne1, info.edges.ne2 ]
                                    else [ info.edges.ne1, info.edges.ne2 ]
        in
        noCmd <|         
        initialise_RenameMode ids m2
                          



-- for view


type alias Edges =
    { e1 : EdgeId
    , e2 : EdgeId
    , ne1 : EdgeId
    , ne2 : EdgeId
    }


type alias ViewInfo =
    { edges : Edges
    , graph : Graph NodeLabel EdgeLabel
    }




-- movedNode


squareMode_activeObj : Edges -> List Obj
squareMode_activeObj info =
    [ OEdge info.e1
    , OEdge info.e2
    , OEdge info.ne1
    , OEdge info.ne2
    ]


moveNodeViewInfo : Model -> SquareState -> ( ViewInfo, NodeId, Bool )
moveNodeViewInfo m data =
    let flipIf b x1 x2 = if False then (x2, x1) else (x1, x2) in
    let commute (str1, str2) =                
                   MyDiff.swapDiff (String.toList str1) 
                       (String.toList data.chosenLabel)
                       (String.toList str2)
                       |> Maybe.map String.fromList
                       |> Maybe.withDefault "!"
    in
    let (labelNode, labelEdge1, labelEdge2) = if data.n1ToChosen == not data.n2ToChosen then 
                       (commute (data.n1Label, data.n2Label), 
                       commute <| flipIf data.n1ToChosen data.n1Label data.e2.label.label, 
                       commute <| flipIf data.n1ToChosen data.e1.label.label data.n2Label
                       )
                    else ("", "", "")
    in
    let
        ( ( g, n ), created ) =
            mayCreateTargetNode m labelNode
    in
    {- let
        edges =
            makeEdges data n
    in -}
    let make_EdgeId n1 n2 isTo =
           if isTo then
               ( n1, n2 )
           else
               ( n2, n1 )
    in
    let (e1n1, e1n2) = make_EdgeId data.n1 n <| nToMoved data.n1ToChosen data.n2ToChosen in
    let (e2n1, e2n2) = make_EdgeId data.n2 n <| nToMoved data.n2ToChosen data.n1ToChosen in
    
    let (g1, ne1) = Graph.newEdge g e1n1 e1n2 <| GraphDefs.newEdgeLabel labelEdge1 ArrowStyle.empty in
    let (g2, ne2) = Graph.newEdge g1 e2n1 e2n2 <| GraphDefs.newEdgeLabel labelEdge2 ArrowStyle.empty in
    
        
            {- Graph.newEdge 
            (Graph.newEdge g edges.ne1 GraphDefs.emptyEdge)
            edges.ne2 
            GraphDefs.emptyEdge
             -}
    
    let edges = makeEdges data ne1 ne2 in
    ( { graph = g2, edges = edges }, n, created )


nToMoved : Bool -> Bool -> Bool
nToMoved nToChosen otherNToChosen =
    if nToChosen == otherNToChosen then
        not nToChosen

    else
        nToChosen


{- makeEdges : SquareModeData -> NodeId -> Edges
makeEdges data movedNode =
    { e1 = make_EdgeId data.n1 data.chosenNode data.n1ToChosen
    , e2 = make_EdgeId data.n2 data.chosenNode data.n2ToChosen
    , ne1 = make_EdgeId data.n1 movedNode <| nToMoved data.n1ToChosen data.n2ToChosen
    , ne2 = make_EdgeId data.n2 movedNode <| nToMoved data.n2ToChosen data.n1ToChosen --,

    -- movedNode = movedNode
    }
 -}
makeEdges : SquareState -> EdgeId -> EdgeId -> Edges
makeEdges data ne1 ne2 =
    { e1 = data.e1.id
    , e2 = data.e2.id
    , ne1 = ne1
    , ne2 = ne2    
    -- movedNode = movedNode
    }


stateInfo : Model -> SquareState -> ViewInfo
stateInfo m s =
            let
                ( info, _, _ ) =
                    moveNodeViewInfo m s
            in
            info

     


graphDrawingFromInfo :
    Edges ->
     Graph NodeDrawingLabel EdgeDrawingLabel
    -> Graph NodeDrawingLabel EdgeDrawingLabel
graphDrawingFromInfo info g =    
    List.foldl graphMakeActive g (squareMode_activeObj info)


graphDrawing : Model -> SquareState -> Graph NodeDrawingLabel EdgeDrawingLabel
graphDrawing m state =
    let
        info =
            stateInfo m state
    in
    collageGraphFromGraph m info.graph
        |> graphDrawingFromInfo info.edges


update : SquareState -> Msg -> Model -> ( Model, Cmd Msg )
update state msg model =
    let next finish = nextStep model finish state in
    case msg of   

   
        KeyChanged False (Character 's') ->
            
                    square_updatePossibility model state.configuration state.chosenNode

        KeyChanged False (Control "Escape") -> switch_Default model
        MouseClick -> next False          
        KeyChanged False (Control "Enter") -> next True
    --     TabInput -> Just <| ValidateNext
        KeyChanged False (Control "Tab") -> next False

      
        _ -> noCmd model

help : String
help =
            "[ESC] cancel, [click] name the point (if new), "
             ++ "[RET] terminate the square creation, "
             ++ " alternative possible [s]quares."
             
      