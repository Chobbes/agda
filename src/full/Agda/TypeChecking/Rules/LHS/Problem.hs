-- {-# LANGUAGE CPP #-}
{-# LANGUAGE DeriveFoldable #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Agda.TypeChecking.Rules.LHS.Problem where

import Prelude hiding (null)

import Data.Foldable ( Foldable )
import Data.Maybe ( fromMaybe )
import Data.Monoid (Monoid, mempty, mappend, mconcat)
import Data.Traversable

import Agda.Syntax.Common
import Agda.Syntax.Literal
import Agda.Syntax.Position
import Agda.Syntax.Internal
import Agda.Syntax.Internal.Pattern
import qualified Agda.Syntax.Abstract as A

import Agda.TypeChecking.Substitute
import Agda.TypeChecking.Substitute.Pattern
import Agda.TypeChecking.Pretty

import Agda.Utils.Null
import Agda.Utils.Permutation

type Substitution   = [Maybe Term]
type FlexibleVars   = [FlexibleVar Nat]

-- | When we encounter a flexible variable in the unifier, where did it come from?
--   The alternatives are ordered such that we will assign the higher one first,
--   i.e., first we try to assign a @DotFlex@, then...
data FlexibleVarKind
  = RecordFlex [FlexibleVarKind]
      -- ^ From a record pattern ('ConP').
      --   Saves the 'FlexibleVarKind' of its subpatterns.
  | ImplicitFlex -- ^ From a hidden formal argument or underscore ('WildP').
  | DotFlex      -- ^ From a dot pattern ('DotP').
  deriving (Eq, Show)

-- | Flexible variables are equipped with information where they come from,
--   in order to make a choice which one to assign when two flexibles are unified.
data FlexibleVar a = FlexibleVar
  { flexHiding :: Hiding
  , flexKind   :: FlexibleVarKind
  , flexVar    :: a
  } deriving (Eq, Show, Functor, Foldable, Traversable)

instance LensHiding (FlexibleVar a) where
  getHiding     = flexHiding
  mapHiding f x = x { flexHiding = f (flexHiding x) }

defaultFlexibleVar :: a -> FlexibleVar a
defaultFlexibleVar a = FlexibleVar Hidden ImplicitFlex a

flexibleVarFromHiding :: Hiding -> a -> FlexibleVar a
flexibleVarFromHiding h a = FlexibleVar h ImplicitFlex a

data FlexChoice = ChooseLeft | ChooseRight | ChooseEither | ExpandBoth
  deriving (Eq, Show)

instance Monoid FlexChoice where
  mempty = ChooseEither

  ExpandBoth   `mappend` _            = ExpandBoth
  _            `mappend` ExpandBoth   = ExpandBoth
  ChooseEither `mappend` y            = y
  x            `mappend` ChooseEither = x
  ChooseLeft   `mappend` ChooseRight  = ExpandBoth -- If there's dot patterns on both sides,
  ChooseRight  `mappend` ChooseLeft   = ExpandBoth -- we need to eta-expand
  ChooseLeft   `mappend` ChooseLeft   = ChooseLeft
  ChooseRight  `mappend` ChooseRight  = ChooseRight

class ChooseFlex a where
  chooseFlex :: a -> a -> FlexChoice

instance ChooseFlex FlexibleVarKind where
  chooseFlex DotFlex         DotFlex         = ChooseEither
  chooseFlex DotFlex         _               = ChooseLeft
  chooseFlex _               DotFlex         = ChooseRight
  chooseFlex (RecordFlex xs) (RecordFlex ys) = chooseFlex xs ys
  chooseFlex (RecordFlex xs) y               = chooseFlex xs (repeat y)
  chooseFlex x               (RecordFlex ys) = chooseFlex (repeat x) ys
  chooseFlex ImplicitFlex    ImplicitFlex    = ChooseEither

instance ChooseFlex a => ChooseFlex [a] where
  chooseFlex xs ys = mconcat $ zipWith chooseFlex xs ys

instance ChooseFlex Hiding where
  chooseFlex Hidden   Hidden   = ChooseEither
  chooseFlex Hidden   _        = ChooseLeft
  chooseFlex _        Hidden   = ChooseRight
  chooseFlex Instance Instance = ChooseEither
  chooseFlex Instance _        = ChooseLeft
  chooseFlex _        Instance = ChooseRight
  chooseFlex _        _        = ChooseEither

instance ChooseFlex Int where
  chooseFlex x y = case compare x y of
    LT -> ChooseLeft
    EQ -> ChooseEither
    GT -> ChooseRight

instance (ChooseFlex a) => ChooseFlex (FlexibleVar a) where
  chooseFlex (FlexibleVar h1 f1 i1) (FlexibleVar h2 f2 i2) =
    firstChoice [chooseFlex f1 f2, chooseFlex h1 h2, chooseFlex i1 i2]
      where
        firstChoice :: [FlexChoice] -> FlexChoice
        firstChoice []                  = ChooseEither
        firstChoice (ChooseEither : xs) = firstChoice xs
        firstChoice (x            : _ ) = x


-- | State of typechecking a LHS; input to 'split'.
--   [Ulf Norell's PhD, page. 35]
--
--   In @Problem ps p delta@,
--   @ps@ are the user patterns of supposed type @delta@.
--   @p@ is the pattern resulting from the splitting.
data Problem' p = Problem
  { problemInPat  :: [NamedArg A.Pattern]  -- ^ User patterns.
  , problemOutPat :: p                       -- ^ Patterns after splitting.
  , problemTel    :: Telescope               -- ^ Type of in patterns.
  , problemRest   :: ProblemRest             -- ^ Patterns that cannot be typed yet.
  }
  deriving Show

-- | The de Bruijn indices in the pattern refer to positions
--   in the list of abstract patterns in the problem, counted
--   from the back.
type Problem     = Problem' [NamedArg DeBruijnPattern]
type ProblemPart = Problem' ()

-- | User patterns that could not be given a type yet.
--
--   Example:
--   @
--      f : (b : Bool) -> if b then Nat else Nat -> Nat
--      f true          = zero
--      f false zero    = zero
--      f false (suc n) = n
--   @
--   In this sitation, for clause 2, we construct an initial problem
--   @
--      problemInPat = [false]
--      problemTel   = (b : Bool)
--      problemRest.restPats = [zero]
--      problemRest.restType = if b then Nat else Nat -> Nat
--   @
--   As we instantiate @b@ to @false@, the 'restType' reduces to
--   @Nat -> Nat@ and we can move pattern @zero@ over to @problemInPat@.

data ProblemRest = ProblemRest
  { restPats :: [NamedArg A.Pattern]
    -- ^ List of user patterns which could not yet be typed.
  , restType :: Arg Type
    -- ^ Type eliminated by 'restPats'.
    --   Can be 'Irrelevant' to indicate that we came by
    --   an irrelevant projection and, hence, the rhs must
    --   be type-checked in irrelevant mode.
  }
  deriving Show

data Focus
  = Focus
    { focusCon      :: QName
    , focusPatOrigin:: ConPOrigin -- ^ Do we come from an implicit or record pattern?
    , focusConArgs  :: [NamedArg A.Pattern]
    , focusRange    :: Range
    , focusOutPat   :: [NamedArg DeBruijnPattern]
    , focusDatatype :: QName
    , focusParams   :: [Arg Term]
    , focusIndices  :: [Arg Term]
    , focusType     :: Type -- ^ Type of variable we are splitting, kept for record patterns.
    }
  | LitFocus Literal [NamedArg DeBruijnPattern] Type

-- | Result of 'splitProblem':  Determines position for the next split.
data SplitProblem

  = -- | Split on constructor pattern.
    Split
      { splitLPats   :: ProblemPart
        -- ^ The typed user patterns left of the split position.
        --   Invariant: @'problemRest' == empty@.
      , splitAsNames :: [Name]
        -- ^ The as-bindings for the focus.
      , splitFocus   :: Arg Focus
        -- ^ How to split the variable at the split position.
      , splitRPats   :: Abs ProblemPart
        -- ^ The typed user patterns right of the split position.
      }

  | -- | Split on projection pattern.
    SplitRest
      { splitProjection :: Arg QName
        -- ^ The projection could be belonging to an irrelevant record field.
      , splitRestType   :: Type
      }

-- | Put a typed pattern on the very left of a @SplitProblem@.
consSplitProblem
  :: NamedArg A.Pattern -- ^ @p@ A pattern.
  -> ArgName              -- ^ @x@ The name of the argument (from its type).
  -> Dom Type           -- ^ @t@ Its type.
  -> SplitProblem         -- ^ The split problem, containing 'splitLPats' @ps;xs:ts@.
  -> SplitProblem         -- ^ The result, now containing 'splitLPats' @(p,ps);(x,xs):(t,ts)@.
consSplitProblem p x dom s@SplitRest{}              = s
consSplitProblem p x dom s@Split{ splitLPats = ps } = s{ splitLPats = consProblem' ps }
  where
  consProblem' (Problem ps () tel pr) =
    Problem (p:ps) () (ExtendTel dom $ Abs x tel) pr

-- | Instantiations of a dot pattern with a term.
--   `Maybe e` if the user wrote a dot pattern .e
--   `Nothing` if this is an instantiation of an implicit argument or an underscore _
data DotPatternInst = DPI
  { dotPatternUserExpr :: Maybe A.Expr
  , dotPatternInst     :: Term
  , dotPatternType     :: Dom Type
  }
data AsBinding      = AsB Name Term Type

-- | State worked on during the main loop of checking a lhs.
data LHSState = LHSState
  { lhsProblem :: Problem
  , lhsSubst   :: PatternSubstitution
  , lhsDPI     :: [DotPatternInst]
  , lhsAsB     :: [AsBinding]
  }

instance Subst Term ProblemRest where
  applySubst rho p = p { restType = applySubst rho $ restType p }

instance Subst Term (Problem' p) where
  applySubst rho p = p { problemTel  = applySubst rho $ problemTel p
                       , problemRest = applySubst rho $ problemRest p }

instance Subst Term DotPatternInst where
  applySubst rho (DPI e v a) = uncurry (DPI e) $ applySubst rho (v,a)

instance Subst Term AsBinding where
  applySubst rho (AsB x v a) = uncurry (AsB x) $ applySubst rho (v, a)

instance PrettyTCM DotPatternInst where
  prettyTCM (DPI me v a) = sep
    [ prettyA e <+> text "="
    , nest 2 $ prettyTCM v <+> text ":"
    , nest 2 $ prettyTCM a
    ]
    where e = fromMaybe underscore me

instance PrettyTCM AsBinding where
  prettyTCM (AsB x v a) =
    sep [ prettyTCM x <> text "@" <> parens (prettyTCM v)
        , nest 2 $ text ":" <+> prettyTCM a
        ]

instance Null ProblemRest where
  null  = null . restPats
  empty = ProblemRest { restPats = [], restType = defaultArg typeDontCare }

instance Null a => Null (Problem' a) where
  null p = null (problemInPat p) && null (problemRest p)
  empty  = Problem empty empty empty empty
