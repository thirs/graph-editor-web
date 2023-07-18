module Format.Version9 exposing (Graph, Node, ArrowStyle, Edge, toJSGraph, fromJSGraph, version)

import Polygraph as Graph exposing (Graph)
import Geometry.Point exposing (Point)
import ArrowStyle
import GraphDefs exposing (EdgeLabel, NodeLabel)
import Format.GraphInfo exposing (GraphInfo)
import GraphDefs exposing (EdgeType(..))
import Drawing.Color as Color

version = 9

type alias ArrowStyle = { tail : String, head : String, double : Bool
   , dashed : Bool, bend : Float, alignment : String, 
   position : Float, color : String }

emptyArrowStyle : ArrowStyle
emptyArrowStyle = ArrowStyle "" "" False False 0 "" 0 "black"

type alias Edge = { label : String, style : ArrowStyle, isPullshout : Bool,
       zindex : Int }

pullshoutEdge : Int -> Edge
pullshoutEdge z = Edge "" emptyArrowStyle True z

type alias Node = { pos : Point , label : String, isMath : Bool}
type alias Graph = { 
      nodes: List (Graph.Node Node),
      edges: List (Graph.Edge Edge),
      sizeGrid : Int,
      latexPreamble : String}

fromEdgeLabel : EdgeLabel -> Edge
fromEdgeLabel e = 
   case e.details of
       PullshoutEdge -> pullshoutEdge e.zindex
       NormalEdge {label, style} ->
            { label = label,
              isPullshout = False,       
              style = { tail = ArrowStyle.tailToString style.tail
               , head = ArrowStyle.headToString style.head
               , alignment = ArrowStyle.alignmentToString style.labelAlignment
               , double = style.double
               , dashed = style.dashed
               , bend = style.bend
               , position = style.labelPosition
               , color = Color.toString style.color
               },
               zindex = e.zindex               
            }
     
toEdgeLabel : Edge -> EdgeLabel
toEdgeLabel { label, style, isPullshout, zindex } = 
   { selected = False, weaklySelected = False,
     zindex = zindex,
     details = 
       if isPullshout then PullshoutEdge else
         NormalEdge { label = label,       
           style = { tail = ArrowStyle.tailFromString style.tail
                   , head = ArrowStyle.headFromString style.head
                   , double = style.double
                   , dashed = style.dashed
                   , bend = style.bend
                   , color = Color.fromString style.color
                   , labelAlignment = ArrowStyle.alignmentFromString style.alignment
                   , labelPosition = style.position 
                                     |> min 0.9
                                     |> max 0.1                                 
                   }
         , dims = Nothing
         }
   }




fromNodeLabel : NodeLabel -> Node
fromNodeLabel { pos, label, isMath } = { pos = pos, label = label, isMath = isMath}

toNodeLabel : Node -> NodeLabel
toNodeLabel { pos, label, isMath } = { pos = pos, label = label
   , dims = Nothing, selected = False, weaklySelected = False, isMath = isMath}





toJSGraph : GraphInfo -> Graph
toJSGraph m =
          let g = m.graph in
          let gjs = g
                   |> Graph.map 
                    (\_ -> fromNodeLabel)
                    (\_ -> fromEdgeLabel) 
                   |> Graph.normalise           
          in
          let nodes = Graph.nodes gjs
              edges = Graph.edges gjs
          in
          {nodes = nodes, edges = edges, sizeGrid = m.sizeGrid,
          latexPreamble = m.latexPreamble}



fromJSGraph : Graph -> GraphInfo
fromJSGraph { nodes, edges, sizeGrid, latexPreamble } = 
       { graph = Graph.fromNodesAndEdges nodes edges
                  |> Graph.map (\_ -> toNodeLabel) (\_ -> toEdgeLabel),
         sizeGrid = sizeGrid,
         latexPreamble = latexPreamble }
