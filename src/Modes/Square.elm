module Modes.Square exposing (graphCollage, initialise, update)

import Collage exposing (..)
import Collage.Layout exposing (..)
import Color exposing (..)
import Graph exposing (..)
import GraphCollage exposing (..)
import GraphExtra as Graph exposing (EdgeId, make_EdgeId)
import IntDict
import Maybe exposing (withDefault)
import Model exposing (..)
import Msg exposing (..)


mayFocus : SquareStep -> Cmd Msg
mayFocus step =
    case step of
        SquareMoveNode _ ->
            Cmd.none

        _ ->
            focusLabelInput


possibleSquareStates : NodeContext a b -> List SquareModeData
possibleSquareStates nc =
    -- Boolean: is it going to the node?
    let
        ins =
            IntDict.keys nc.incoming |> List.map (\x -> ( x, True ))

        outs =
            IntDict.keys nc.outgoing |> List.map (\x -> ( x, False ))
    in
    ins
        ++ outs
        |> uniquePairs
        |> List.map
            (\( ( n1, i1 ), ( n2, i2 ) ) ->
                { chosenNode = nc.node.id

                --   -- we don't care
                -- , movedNode = 0
                , n1 = n1
                , n2 = n2
                , n1ToChosen = i1
                , n2ToChosen = i2
                }
            )



-- from ListExtra package


uniquePairs : List a -> List ( a, a )
uniquePairs xs =
    case xs of
        [] ->
            []

        x :: xs_ ->
            List.map (\y -> ( x, y )) xs_ ++ uniquePairs xs_


getAt : Int -> List a -> Maybe a
getAt idx xs =
    List.head <| List.drop idx xs


square_setPossibility : Int -> Graph a b -> NodeId -> Maybe SquareState
square_setPossibility idx g chosenNode =
    Graph.get chosenNode g
        |> Maybe.map possibleSquareStates
        |> Maybe.andThen
            (\possibilities ->
                possibilities
                    |> getAt idx
                    |> Maybe.map
                        (\s ->
                            { data = s
                            , step =
                                SquareMoveNode
                                    (modBy (List.length possibilities) (idx + 1))
                            }
                        )
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
    m.activeObj
        |> objToNode
        |> Maybe.map (square_updatePossibility m 0)
        |> Maybe.withDefault (noCmd m)


nextStep : Model -> Bool -> SquareState -> ( Model, Cmd Msg )
nextStep model validate state =
    let
        renamableNextMode m =
            let
                graph =
                    if validate then
                        m.graph

                    else
                        graphRenameObj m.graph (renamableFromState state) ""
            in
            noCmd { m | graph = graph }
    in
    let
        renamableNextStep step =
            renamableNextMode { model | mode = SquareMode { state | step = step } }
    in
    case state.step of
        SquareMoveNode _ ->
            if not validate then
                switch_Default model

            else
                let
                    ( info, movedNode, created ) =
                        moveNodeViewInfo model state.data
                in
                noCmd
                    { model
                        | graph = info.graph
                        , mode =
                            SquareMode <|
                                { state
                                    | step =
                                        if created then
                                            SquareEditNode movedNode

                                        else
                                            SquareEditEdge1 movedNode
                                }
                    }

        SquareEditNode mn ->
            renamableNextStep <| SquareEditEdge1 mn

        SquareEditEdge1 mn ->
            renamableNextStep <| SquareEditEdge2 mn

        SquareEditEdge2 mn ->
            renamableNextMode
                { model
                    | activeObj = ONode mn
                    , mode = DefaultMode
                }



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


renamable : SquareStep -> Edges -> Obj
renamable step info =
    case step of
        SquareEditNode movedNode ->
            ONode movedNode

        SquareEditEdge1 _ ->
            OEdge <| info.ne1

        SquareEditEdge2 _ ->
            OEdge <| info.ne2

        _ ->
            ONothing


renamableFromState : SquareState -> Obj
renamableFromState state =
    let
        renamableMoved =
            makeEdges state.data
                >> renamable state.step
    in
    case state.step of
        SquareEditNode m ->
            renamableMoved m

        SquareEditEdge1 m ->
            renamableMoved m

        SquareEditEdge2 m ->
            renamableMoved m

        SquareMoveNode _ ->
            ONothing



-- movedNode


squareMode_activeObj : Edges -> List Obj
squareMode_activeObj info =
    [ OEdge info.e1
    , OEdge info.e2
    , OEdge info.ne1
    , OEdge info.ne2
    ]


moveNodeViewInfo : Model -> SquareModeData -> ( ViewInfo, NodeId, Bool )
moveNodeViewInfo m data =
    let
        ( ( g, n ), created ) =
            mayCreateTargetNode m ""
    in
    let
        edges =
            makeEdges data n
    in
    let
        g2 =
            Graph.addEdge (Graph.addEdge g edges.ne1 "") edges.ne2 ""
    in
    ( { graph = g2, edges = edges }, n, created )


nToMoved : Bool -> Bool -> Bool
nToMoved nToChosen otherNToChosen =
    if nToChosen == otherNToChosen then
        not nToChosen

    else
        nToChosen


makeEdges : SquareModeData -> NodeId -> Edges
makeEdges data movedNode =
    { e1 = make_EdgeId data.n1 data.chosenNode data.n1ToChosen
    , e2 = make_EdgeId data.n2 data.chosenNode data.n2ToChosen
    , ne1 = make_EdgeId data.n1 movedNode <| nToMoved data.n1ToChosen data.n2ToChosen
    , ne2 = make_EdgeId data.n2 movedNode <| nToMoved data.n2ToChosen data.n1ToChosen --,

    -- movedNode = movedNode
    }


stateInfo : Model -> SquareState -> ViewInfo
stateInfo m s =
    let
        defaultView movedNode =
            { graph = m.graph, edges = makeEdges s.data movedNode }
    in
    case s.step of
        SquareMoveNode _ ->
            let
                ( info, _, _ ) =
                    moveNodeViewInfo m s.data
            in
            info

        SquareEditNode movedNode ->
            defaultView movedNode

        SquareEditEdge1 movedNode ->
            defaultView movedNode

        SquareEditEdge2 movedNode ->
            defaultView movedNode


graphCollageFromInfo :
    Edges
    -> SquareStep
    -> Graph NodeCollageLabel EdgeCollageLabel
    -> Graph NodeCollageLabel EdgeCollageLabel
graphCollageFromInfo info step g =
    let
        g2 =
            g |> graphMakeEditable (renamable step info)
    in
    List.foldl graphMakeActive g2 (squareMode_activeObj info)


graphCollage : Model -> SquareState -> Graph NodeCollageLabel EdgeCollageLabel
graphCollage m state =
    let
        info =
            stateInfo m state
    in
    collageGraphFromGraph m info.graph
        |> graphCollageFromInfo info.edges state.step


update : SquareState -> Msg -> Model -> ( Model, Cmd Msg )
update state msg model =
    case msg of
        KeyChanged False (Control "Escape") ->
            nextStep model False state

        KeyChanged False (Control "Enter") ->
            nextStep model True state

        MouseClick ->
            nextStep model True state

        EdgeLabelEdit e s ->
            noCmd { model | graph = graphRenameObj model.graph (OEdge e) s }

        NodeLabelEdit n s ->
            noCmd { model | graph = graphRenameObj model.graph (ONode n) s }

        KeyChanged False (Character 's') ->
            case state.step of
                SquareMoveNode idx ->
                    square_updatePossibility model idx state.data.chosenNode

                _ ->
                    noCmd model

        -- I don't know why this is necessary, but I may need to refocus
        NodeLeave _ ->
            ( model, mayFocus state.step )

        NodeEnter _ ->
            ( model, mayFocus state.step )

        _ ->
            noCmd model