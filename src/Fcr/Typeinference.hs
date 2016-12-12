module Fcr.Typeinference where

import Fcr.Syntax
import Fcr.Interaction
import Fcr.Monad
import Fcr.Rewrite hiding (merge')

import Fcr.PrettyPrinting
import Fcr.Typecheck
import Control.Monad.State
import Text.PrettyPrint
import Data.List
import Data.Char
import Debug.Trace

constrProof :: Name -> [ProofState] -> KSubst -> Exp -> Either Doc Exp
constrProof n init ks exp =
  let finals = construction' n ks init exp in
  case [s | s <- finals, success s] of
        (_, pf, _, _, _):_ -> Right pf -- trace (show $ disp pf) $ 
        [] -> let rs = map (\ a -> case a of
                               (_, _, (_,g,_):_ , m, _) -> case m of
                                                Nothing -> text "unfinish goal" <+> disp g
                                                Just m' -> m'
                               (_, _, [] , m, _) -> case m of
                                                Nothing -> text "strange" 
                                                Just m' -> m' 
                           ) finals
              in Left $ sep (map (\ (d, i) -> text "Wrong situation" <+> int i $$ nest 2 d)
                             $ zip rs [1..])

env2 = [("H", KArrow Star (KArrow Star Star)), ("J", KArrow Star Star), ("G", KArrow Star Star), ("S", KArrow Star Star)]
exp1 = (Lambda "a1" Nothing
        (Lambda "a2" Nothing
         (Lambda "a3" Nothing
          (App (Var "a3")
           (App (Var "a1")
            (App (Var "a2")
             (App (App (App (Var "h")
                        (Lambda "b1" Nothing (App (Var "a1") (App (Var "a2") (Var "b1")))))
                   (Lambda "b1" Nothing (App (Var "a2") (Var "b1"))))
              (Lambda "b1" Nothing (App (Var "a3") (Var "b1"))))))))))

f1 = Forall "p'" (Forall "f" (Forall "x" (Forall "z" (Imply (Forall "p" (Forall "x" (Forall "y" (Imply (PApp (Var "p") (PApp (PApp (Var "f") (PApp (Const "S") (Var "x"))) (PApp (Const "G") (PApp (PApp (Const "H") (Var "x")) (Var "z"))))) (PApp (Var "p") (PApp (PApp (Var "f") (Var "x")) (Var "y"))))))) (Imply (Forall "p" (Forall "x" (Forall "y" (Imply (PApp (Var "p") (PApp (PApp (Const "H") (Var "x")) (PApp (Const "S") (Var "y")))) (PApp (Var "p") (PApp (PApp (Const "H") (PApp (Const "S") (Var "x"))) (Var "y"))))))) (Imply (Forall "p" (Forall "x" (Forall "y" (Imply (PApp (Var "p") (PApp (Const "J") (Var "y"))) (PApp (Var "p") (PApp (Const "G") (PApp (PApp (Const "H") (Var "x")) (Var "y")))))))) (PApp (Var "p'") (PApp (PApp (Var "f") (PApp (Const "S") (Var "x"))) (PApp (Const "G") (PApp (PApp (Const "H") (Var "x")) (Var "z")))))))))))

g2 = PApp (Var "p'") (PApp (PApp (Var "f") (PApp (Const "S") (PApp (Const "S") (Var "x")))) (PApp (Const "G") (PApp (PApp (Const "H") (Var "x")) (PApp (Const "S") (Var "z")))))

h2 = PApp (Var "p1fresh") (PApp (PApp (Const "H") (PApp (Const "S") (Var "x2fresh"))) (Var "y3fresh"))
initstate1 = [("h", f1, [([], f1, [("h", f1)])], Nothing, 0)]
man1 = case [s | s <- construction "h" env2 initstate1 exp1, success s] of
        (_, pf, _, _, _):_ -> disp pf
man3 = construction "h" env2 initstate1 (Var "h")

g1 = PApp (Var "p'") (PApp (PApp (Var "f") (PApp (Const "S") (PApp (Const "S") (Var "x")))) (PApp (Const "G") (PApp (PApp (Const "H") (Var "x")) (PApp (Const "S") (Var "z")))))

h1 = PApp (Var "p'1") (PApp (PApp (Var "f2") (PApp (Const "S") (Var "x3"))) (PApp (Const "G") (PApp (PApp (Const "H") (Var "x3")) (Var "z4"))))
man2 = runHMatch env2 h1 g1

l1 = PApp (Const "`p8") (PApp (Var "a5") (Const "`y9"))
l2 = PApp (Const "`p8") (PApp (Const "`a0") (PApp (Const "`b1") (Const "`y9")))
tl1 = runHMatch [] l1 l2 --sep [ disp s | s <- evalState (hmatch [] l1 l2) 0] 

success :: ProofState -> Bool
success (gn,pf,[], Nothing, i) = True
success _ = False


display s  = sep [ brackets (sep $ helper q) | (_,_,q ,Nothing, _) <- s ]
helper [] = [empty]
helper ((_,g,_):xs) = disp g : helper xs

-- a wraper on construction just to handle loop better.
construction' :: Name -> KSubst -> [ProofState] -> Exp -> [ProofState]

construction' n ks init a@(App t_1 t_2) =
  let  new = map (\ x -> intros x []) init 
  in construction n ks new a
construction' n ks init a = construction n ks init a     

construction :: Name -> KSubst -> [ProofState] -> Exp -> [ProofState]
--construction n ks init exp | trace (show ( n) ++ "-- " ++show (disp exp) ++ "--" ++ (show $ display init)) False = undefined
construction n ks init (Var v) =
  concat $ map (\ x -> applyH ks x v) init

construction n ks init (Const v) =
  concat $ map (\ x -> applyH ks x v) init

construction n ks init a@(Lambda x Nothing t) =
  let (vars, b) = (map fst $ viewLVars a, viewLBody a)
      new = map (\ x -> intros x vars) init 
  in construction n ks new b

construction n ks init (App (Const k) p2) =
  let next = concat $ map (\ x -> applyH ks x k) init
  in construction n ks next p2

construction n ks init (App (Var v) p2) =
  let next = concat $ map (\ x -> applyH ks x v) init
  in construction n ks next p2

--  x App (App y z) q
construction n ks init a@(App p1 p2) = 
  case flatten a of
    (Var v): xs ->
      let next = concat $ map (\ x -> applyH ks x v) init
      in foldl (\ z x -> construction n ks z x) next xs
    (Const v): xs ->
      let next = concat $ map (\ x -> applyH ks x v) init
      in foldl (\ z x -> construction n ks z x) next xs
         
--    a -> error $ show a

-- construction n ks init a@(App p1 p2) =

      

-- Second order matching, using Gilles Dowek's terminology in his tutorial.
-- tips: the less number of higher order variable, the less number of
-- possible substitution we get. 

kenv = [("Z", Star), ("S", KArrow Star Star), ("T", Star), ("d", KArrow Star (KArrow Star Star))]
t1 = PApp (Var "p") (PApp (PApp (Const "d") (Const "Z")) (Const "Z"))
t1' = PApp (Var "p1") (PApp (PApp (Const "d") (Const "Z")) (Const "Z"))
t2 = (PApp (PApp (Var "d1") (Const "Z")) (PApp (Const "S") (Const "Z")))
t3 = PApp (Const "B") (PApp (Var "l") (PApp (Const "B") (Var "x")))
t4 = PApp (Const "B") (PApp (Var "l1") (PApp (Const "A") (PApp (Const "B") (Var "y"))))
t5 = PApp (PApp (PApp (PApp (Var "g") (Const "T")) (Const "T")) (Const "Z")) (PApp (Var "s") (Const "Z"))
t6 = PApp (PApp (PApp (PApp (Var "g1") (Const "T")) (Const "T")) (PApp (Const "S") (Const "Z")))
     (PApp (Var "s1") (PApp (Var "s1") (Const "Z")))
-- hmatch :: MonadPlus m => KSubst -> Exp -> Exp -> StateT Int m [Subst]
-- test1 :: [[Subst]]


a1 = evalState (hmatch kenv t1' t1) 0
a2 = wellKind (free t1') kenv a1
a3 = runHMatch [("B", KArrow Star Star), ("A", Star)] (PApp (Const "B") (Var "q")) (PApp (Const "B") (Const "A"))
a4 = runHMatch [("A", KArrow Star Star), ("B", KArrow Star Star)] t3 t4
a5 = runHMatch kenv t5 t6
test1 = sep $ map (\ x -> text "[" <+> disp x <+> text "]") $ a2
test2 = length a1
test3 = sep $ map (\ x -> text "[" <+> disp x <+> text "]") $ a4
test4 = length a2
-- test5 = sep $ map (\ x -> text "[" <+> disp x <+> text "]") $ man2