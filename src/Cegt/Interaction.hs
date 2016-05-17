module Cegt.Interaction where
import Cegt.Syntax
import Cegt.PrettyPrinting
import Cegt.Rewrite
import Data.List
import Data.Char

import Control.Monad.State
import Text.PrettyPrint


fail' x = fail $ show x

prfConstr :: [Tactic] -> StateT ProofState (Either Doc) (Name, Exp)
prfConstr [] = do ps <- get  -- (Name, Exp, [(Pos, Exp, PfEnv)])
                  case ps of
                    (n, pf, []) -> return (n, pf)
                    (n, pf, (_,g,_):as) -> fail' $ text "unfinished goal" <+> disp g
prfConstr (Coind:xs) = do ps@(n,_,_) <- get
                          case coind ps of
                            Nothing -> fail' $
                                       text "fail to use coind tactic, in the proof of lemma"
                                       <+> disp n
                            Just ps' -> put ps' >> prfConstr xs
                                           
prfConstr ((Intros ns):xs) = do ps <- get
                                put $ intros ps ns 
                                prfConstr xs

prfConstr ((Apply n ts):xs) = do ps@(n,_,_) <- get
                                 case apply ps n ts of
                                   Nothing -> fail' $
                                              text "fail to use the tactic: apply"
                                              <+> disp n <+> hcat (map disp ts) $$
                                              text "in the proof of lemma" <+> disp n
                                   Just ps' -> put ps' >> prfConstr xs

prfConstr ((Use n ts):xs) = do ps@(n,_,_) <- get
                               case apply ps n ts of
                                   Nothing -> fail' $
                                              text "fail to use the tactic: use"
                                              <+> disp n <+> hcat (map disp ts)
                                              $$ text "in the proof of lemma" <+> disp n
                                   Just ps' -> put ps' >> prfConstr xs


                            


normalize :: Exp -> Exp
normalize (Var a) = Var a
-- normalize Star = Star
normalize (Const a) = Const a
normalize (Lambda x t) = Lambda x (normalize t)
normalize (App (Lambda x t') t) = runSubst t (Var x) t'
normalize (App (Var x) t) = App (Var x) (normalize t)
normalize (App (Const x) t) = App (Const x) (normalize t)
normalize (App t' t) = case (App (normalize t') (normalize t)) of
                              a@(App (Lambda x t') t) -> normalize a
                              b -> b
normalize (Imply t t') = Imply (normalize t) (normalize t')
normalize (Forall x t) = Forall x (normalize t)
-- normalize a = error $ show a

-- quantify :: Exp -> ([Name], Exp)
-- quantify a@(Arrow t t') = ("p":(free a), Imply (App (Var "p") t') (App (Var "p") t))

type PfEnv = [(Name, Exp)]
type ProofState = (Name, Exp, [(Pos, Exp, PfEnv)])

coind :: ProofState -> Maybe ProofState
coind (g, pf, ([], pf', env):[]) | pf == pf' = Just (g, pf, ([], pf', env++[(g,pf)]):[])
                                 | otherwise = Nothing
coind _ = Nothing

intros :: ProofState -> [Name] -> ProofState
intros (gn, pf, []) ns = (gn, pf, [])
intros (gn, pf, (pos, goal, gamma):res) ns =
  let (vars, head, body) = separate goal
      goal' = head
      lb = length body
      lv = length vars
      num = lv + lb
      impNames = drop lv ns 
      names = ns 
      newLam = foldr (\ a b -> Lambda a b) head names
      pf' = replace pf pos newLam
      newEnv = zip impNames body
      pos' = pos ++ take num streamOne in (gn, pf', (pos',head, gamma++newEnv):res)

streamOne = 1:streamOne

apply :: ProofState -> Name -> [Exp] -> Maybe ProofState
apply (gn, pf, []) k ins = Just (gn, pf, [])
apply (gn, pf, (pos, goal, gamma):res) k ins = 
  case lookup k gamma of
    Nothing -> Nothing
    Just f -> let (vars, head, body) = separate f
                  fresh = map (\ (v, i) -> v ++ show i ++ "fresh") $ zip vars [1..]
                  renaming = zip vars (map Var fresh)
                  sub = zip fresh ins
                  body'' = map (applyE renaming) body
                  head'' = applyE renaming head
                  body' = map normalize $ (map (applyE sub) body'')
                  head' = normalize $ applyE sub head''
              in if head' /= goal then Nothing
                                       -- error $ "error apply" ++ show head' ++ "--" ++ show goal
                                       -- ++ show sub ++ "--" ++ show head 
                 else let np = ins++body'
                          name = case k of
                                   n:_ -> if isUpper n then Const k else Var k
                                   a -> error "unknow error from apply"
                          contm = foldl' (\ z x -> App z x) name np
                          pf' = replace pf pos contm
                          zeros = makeZeros $ length body'
                          ps = map (\ x -> pos++x++[1]) zeros
                          new = map (\(p, g) -> (p, g, gamma)) $ zip ps body'
                      in Just (gn, pf', new++res)  

use :: ProofState -> Name -> [Exp] -> Maybe ProofState
use (gn, pf, []) k ins = Just (gn, pf, [])
use (gn, pf, (pos, goal, gamma):res) k ins = 
  case lookup k gamma of
    Nothing -> Nothing
    Just f -> let (vars, bare) = getVars f
                  fresh = map (\ (v, i) -> v ++ show i ++ "fresh") $ zip vars [1..]
                  renaming = zip vars (map Var fresh)
                  sub = zip fresh ins
                  b'' = applyE renaming bare
                  b' = normalize $ applyE sub b''
                  f' = foldl' (\t x -> Forall x t) b' (free b')
              in if f' `alphaEq` goal then
                   let name = case k of
                                   n:_ -> if isUpper n then Const k else Var k
                                   a -> error "unknow error from apply"
                       contm = foldl' (\ z x -> App z x) name ins
                       pf' = replace pf pos contm
                   in Just (gn, pf', res)  
                 else Nothing
                   
                   

separate f = let (vars, imp) = getVars f
                 (bs, h) = getPre imp
             in (vars, h, bs)
                
getVars :: Exp -> ([Name],Exp)
getVars (Forall x t) = let (xs, t') = getVars t in (x:xs, t')
getVars t = ([], t)

getPre ::  Exp -> ([Exp],Exp)
getPre (Imply x y) = let (bs, t') = getPre y in (x:bs, t')
getPre t = ([], t)

makeZeros 0 = []
makeZeros n | n > 0 = make n : makeZeros (n-1)
stream = 0:stream
make n | n > 0 = take (n-1) stream



                                           
                     
                 
                                                    
