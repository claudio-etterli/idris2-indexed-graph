module Data.Graph.Indexed.Query.BFS

import Data.Queue
import Data.Graph.Indexed
import Data.Graph.Indexed.Query.Util
import Data.Graph.Indexed.Query.Visited
import Data.SnocList

%default total

enqueueE :
     Queue (s, Fin k)
  -> (s -> Fin k -> Either s a)
  -> s
  -> List (Fin k)
  -> Either (Queue (s, Fin k)) a
enqueueE q f st []      = Left q
enqueueE q f st (x::xs) =
  case f st x of
    Right v => Right v
    Left st2 => enqueueE (enqueue q (st2, x)) f st xs

parameters {k : Nat}
           (g : IGraph k e n)

--------------------------------------------------------------------------------
-- Flat BFS traversals
--------------------------------------------------------------------------------

  -- flat BFS implementation for large graphs
  bfsL : Queue (s,Fin k) -> (s -> Fin k -> Either s a) -> MVis k (Maybe a)
  bfsL q f v =
    case dequeue q of
      Nothing => Nothing # v
      Just ((vs,x),q2) =>
       let False # v2 := mvisited x v
             | True # v2 => bfsL q2 f (assert_smaller v v2)
           Left q3 := enqueueE q2 f vs (neighbours g x) | Right v => Just v # v2
        in bfsL q3 f (assert_smaller v $ mvisit x v2)

  -- flat BFS implementation for small graphs
  bfsS : Queue (s,Fin k) -> (s -> Fin k -> Either s a) -> Vis k (Maybe a)
  bfsS q f v =
    case dequeue q of
      Nothing     => (Nothing,v)
      Just ((vs,x),q2) =>
       let False   := visited x v | True => bfsS q2 f (assert_smaller v v)
           Left q3 := enqueueE q2 f vs (neighbours g x) | Right x => (Just x, v)
        in bfsS q3 f (assert_smaller v $ visit x v)

  ||| Traverses the graph in breadth-first order for the given
  ||| start nodes and accumulates the nodes encountered with the
  ||| given function.
  |||
  ||| Unlike `bfsWith`, this takes a list of nodes that are taboo, that is
  ||| that will already be set to `visited`. This allows us exclude certain
  ||| pathways from our search.
  |||
  ||| One use case is to find the shortest cycle containing a given
  ||| edge or sequence of edges.
  export
  limitedBfsWith :
       (taboo : List (Fin k))
    -> (s -> Fin k -> Either s a)
    -> (init : s)
    -> Fin k
    -> Maybe a
  limitedBfsWith taboo acc init x =
    if k < 64
       then fst $ bfsS (fromList [(init,x)]) acc (visitAll taboo ini)
       else visiting' k (bfsL (fromList [(init,x)]) acc . mvisitAll taboo)

  ||| Traverses the graph in breadth-first order for the given
  ||| start nodes and accumulates the nodes encountered with the
  ||| given function.
  export %inline
  bfsWith : (s -> Fin k -> Either s a) -> (init : s) -> Fin k -> Maybe a
  bfsWith = limitedBfsWith []

  ||| Tries to find a shortest path between the two nodes.
  export %inline
  limitedBfs :
       (taboo : List (Fin k))
     -> Fin k
     -> Fin k
     -> Maybe (SnocList (Fin k))
  limitedBfs taboo start end =
    if start == end then Just [< start]
    else
      limitedBfsWith
        taboo
        (\sx,x => if x == end then Right (sx :< x) else Left (sx :< x))
        [<start]
        start

  ||| Tries to find a shortest path between the two nodes.
  export %inline
  bfs : Fin k -> Fin k -> Maybe (SnocList (Fin k))
  bfs = limitedBfs []

----------------------------------------------------------------------------------
---- Generalized Breadth-First Searches
----------------------------------------------------------------------------------

  -- BFS implementation covering a whole connected component for large graphs
  bfsAllL : SnocList s -> Queue (s,Fin k) -> (s -> Fin k -> s) -> MVis k (List s)
  bfsAllL ss q f v =
    case dequeue q of
      Nothing => (ss <>> []) # v
      Just ((vs,x),q2) =>
       let False # v2 := mvisited x v
             | True # v2 => bfsAllL ss q2 f (assert_smaller v v2)
           q3 := enqueueAll q2 (map (\y => (f vs y, y)) $ neighbours g x)
        in bfsAllL (ss :< vs) q3 f (assert_smaller v $ mvisit x v2)

  -- flat BFS implementation for small graphs
  bfsAllS : SnocList s -> Queue (s,Fin k) -> (s -> Fin k -> s) -> Vis k (List s)
  bfsAllS ss q f v =
    case dequeue q of
      Nothing     => (ss <>> [],v)
      Just ((vs,x),q2) =>
       let False   := visited x v | True => bfsAllS ss q2 f (assert_smaller v v)
           q3 := enqueueAll q2 (map (\y => (f vs y, y)) $ neighbours g x)
        in bfsAllS (ss :< vs) q3 f (assert_smaller v $ visit x v)

  ||| Traverses the graph in breadth-first order for the given
  ||| start nodes and accumulates the nodes encountered with the
  ||| given function.
  export
  bfsAllWith : (s -> Fin k -> s) -> (init : s) -> Fin k -> List s
  bfsAllWith acc init x =
    if k < 64
       then fst $ bfsAllS [<] (fromList [(init,x)]) acc ini
       else visiting' k (bfsAllL [<] (fromList [(init,x)]) acc)

  export
  distancesToNode : Fin k -> List (Nat, Fin k)
  distancesToNode x = bfsAllWith (\x,y => (S $ fst x, y)) (0,x) x

----------------------------------------------------------------------------------
---- Shortest Paths
----------------------------------------------------------------------------------

  covering
  shortestL :
       SnocList (SnocList $ Fin k)
    -> Queue (SnocList $ Fin k)
    -> MVis k (List (SnocList $ Fin k))
  shortestL sp q v =
    case dequeue q of
      Nothing => (sp <>> []) # v
      Just (sx@(_:<x),q2) =>
        let False # v2 := mvisited x v | True # v2 => shortestL sp q2 v2
            ns := map (sx :<) (neighbours g x)
         in shortestL (sp :< sx) (enqueueAll q2 ns) (mvisit x v2)
      Just (_,q2) => shortestL sp q2 v

  covering
  shortestS :
       SnocList (SnocList $ Fin k)
    -> Queue (SnocList $ Fin k)
    -> Vis k (List (SnocList $ Fin k))
  shortestS sp q v =
    case dequeue q of
      Nothing => (sp <>> [],v)
      Just (sx@(_:<x),q2) => case x `visited` v of
        True  => shortestS sp q2 v
        False =>
          let ns := map (sx :<) (neighbours g x)
           in shortestS (sp :< sx) (enqueueAll q2 ns) (x `visit` v)
      Just (_,q2) => shortestS sp q2 v

  ||| Computes the shortest paths to all nodes reachable from
  ||| the given starting node. This is a simplified version of
  ||| Dijkstra's algorithm for unweighted edges.
  |||
  ||| Runs in O(n+m) time and O(n) memory.
  export
  shortestPaths : Fin k -> List (SnocList $ Fin k)
  shortestPaths x =
    let q := fromList $ map ([<x] :<) (neighbours g x)
     in assert_total $ if k < 64
          then fst $ shortestS [<] q (x `visit` ini)
          else visiting' k (\v => shortestL [<] q (x `mvisit` v))
