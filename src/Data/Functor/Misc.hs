{-# LANGUAGE CPP #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
#ifdef USE_REFLEX_OPTIMIZER
{-# OPTIONS_GHC -fplugin=Reflex.Optimizer #-}
#endif
-- | This module provides types and functions with no particular theme, but
-- which are relevant to the use of 'Functor'-based datastructures like
-- 'Data.Dependent.Map.DMap'.
module Data.Functor.Misc
  ( -- * Const2
    Const2 (..)
  , unConst2
  , dmapToMap
  , dmapToMapWith
  , mapToDMap
  , weakenDMapWith
    -- * WrapArg
  , WrapArg (..)
    -- * Convenience functions for DMap
  , mapWithFunctorToDMap
  , mapKeyValuePairsMonotonic
  , combineDMapsWithKey
  , EitherTag (..)
  , dmapToThese
  , eitherToDSum
  , dsumToEither
    -- * Deprecated functions
  , sequenceDmap
  , wrapDMap
  , rewrapDMap
  , unwrapDMap
  , unwrapDMapMaybe
  , extractFunctorDMap
  , ComposeMaybe (..)
  ) where

import Control.Applicative (Applicative, (<$>))
import Control.Monad.Identity
import Data.Dependent.Map (DMap)
import qualified Data.Dependent.Map as DMap
import Data.Dependent.Sum
import Data.GADT.Compare
import Data.GADT.Show
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Some (Some)
import qualified Data.Some as Some
import Data.These
import Data.Typeable hiding (Refl)

--------------------------------------------------------------------------------
-- Const2
--------------------------------------------------------------------------------

-- | 'Const2' stores a value of a given type 'k' and ensures that a particular
-- type 'v' is always given for the last type parameter
data Const2 :: * -> x -> x -> * where
  Const2 :: k -> Const2 k v v
  deriving (Typeable)

unConst2 :: Const2 k v v' -> k
unConst2 (Const2 k) = k

deriving instance Eq k => Eq (Const2 k v v')
deriving instance Ord k => Ord (Const2 k v v')
deriving instance Show k => Show (Const2 k v v')
deriving instance Read k => Read (Const2 k v v)

instance Show k => GShow (Const2 k v) where
  gshowToShow (Const2 _) = id

instance (Show k, Show (f v)) => ShowTag (Const2 k v) f where
  showTagToShow (Const2 _) _ = id

instance Eq k => GEq (Const2 k v) where
  geqToEq _ = id
  geqUnify (Const2 _) (Const2 _) _ = id

instance Ord k => GCompare (Const2 k v) where
  gcompareToOrd (Const2 _) = id
  gcompare (Const2 a) (Const2 b) = strengthenOrdering $ compare a b

instance {-# INCOHERENT #-} (Eq k, Eq v) => EqTag (Const2 k v) Identity where
  eqTagToEq (Const2 _) _ = id

instance {-# INCOHERENT #-} Eq k => EqTag (Const2 k v) (Const2 k v) where
  eqTagToEq (Const2 _) _ = id

-- | Convert a 'DMap' to a regular 'Map'
dmapToMap :: DMap (Const2 k v) Identity -> Map k v
dmapToMap = Map.fromDistinctAscList . map (\(Const2 k :=> Identity v) -> (k, v)) . DMap.toAscList

dmapToMapWith :: (f v -> v') -> DMap (Const2 k v) f -> Map k v'
dmapToMapWith f = Map.fromDistinctAscList . map (\(Const2 k :=> v) -> (k, f v)) . DMap.toAscList

-- | Convert a regular 'Map' to a 'DMap'
mapToDMap :: Map k v -> DMap (Const2 k v) Identity
mapToDMap = DMap.fromDistinctAscList . map (\(k, v) -> Const2 k :=> Identity v) . Map.toAscList

-- | Convert a regular 'Map', where the values are already wrapped in a functor,
-- to a 'DMap'
mapWithFunctorToDMap :: Map k (f v) -> DMap (Const2 k v) f
mapWithFunctorToDMap = DMap.fromDistinctAscList . map (\(k, v) -> Const2 k :=> v) . Map.toAscList

weakenDMapWith :: (forall a. v a -> v') -> DMap k v -> Map (Some k) v'
weakenDMapWith f = Map.fromDistinctAscList . map (\(k :=> v) -> (Some.This k, f v)) . DMap.toAscList

--------------------------------------------------------------------------------
-- WrapArg
--------------------------------------------------------------------------------

-- | 'WrapArg' can be used to tag a value in one functor with a type
-- representing another functor.  This was primarily used with dependent-map <
-- 0.2, in which the value type was not wrapped in a separate functor.
data WrapArg :: (k -> *) -> (k -> *) -> * -> * where
  WrapArg :: f a -> WrapArg g f (g a)

deriving instance Eq (f a) => Eq (WrapArg g f (g' a))
deriving instance Ord (f a) => Ord (WrapArg g f (g' a))
deriving instance Show (f a) => Show (WrapArg g f (g' a))
deriving instance Read (f a) => Read (WrapArg g f (g a))

instance GEq f => GEq (WrapArg g f) where
  geqToEq (WrapArg f) = geqToEq f
  geqUnify (WrapArg a) (WrapArg b) = geqUnify a b

instance GCompare f => GCompare (WrapArg g f) where
  gcompareToOrd (WrapArg f) = gcompareToOrd f
  gcompare (WrapArg a) (WrapArg b) = case gcompare a b of
    GLT -> GLT
    GEQ -> GEQ
    GGT -> GGT

--------------------------------------------------------------------------------
-- Convenience functions for DMap
--------------------------------------------------------------------------------

-- | Map over all key/value pairs in a 'DMap', potentially altering the key as
-- well as the value.  The provided function MUST preserve the ordering of the
-- keys, or the resulting 'DMap' will be malformed.
mapKeyValuePairsMonotonic :: (DSum k v -> DSum k' v') -> DMap k v -> DMap k' v'
mapKeyValuePairsMonotonic f = DMap.fromDistinctAscList . map f . DMap.toAscList

{-# INLINE combineDMapsWithKey #-}
-- | Union two 'DMap's of different types, yielding another type.  Each key that
-- is present in either input map will be present in the output.
combineDMapsWithKey :: forall f g h i.
                       GCompare f
                    => (forall a. f a -> These (g a) (h a) -> i a)
                    -> DMap f g
                    -> DMap f h
                    -> DMap f i
combineDMapsWithKey f mg mh = DMap.fromList $ go (DMap.toList mg) (DMap.toList mh)
  where go :: [DSum f g] -> [DSum f h] -> [DSum f i]
        go [] hs = map (\(hk :=> hv) -> hk :=> f hk (That hv)) hs
        go gs [] = map (\(gk :=> gv) -> gk :=> f gk (This gv)) gs
        go gs@((gk :=> gv) : gs') hs@((hk :=> hv) : hs') = case gk `gcompare` hk of
          GLT -> (gk :=> f gk (This gv)) : go gs' hs
          GEQ -> (gk :=> f gk (These gv hv)) : go gs' hs'
          GGT -> (hk :=> f hk (That hv)) : go gs hs'

-- | Extract the values of a 'DMap' of 'EitherTag's.
dmapToThese :: DMap (EitherTag a b) Identity -> Maybe (These a b)
dmapToThese m = case (DMap.lookup LeftTag m, DMap.lookup RightTag m) of
  (Nothing, Nothing) -> Nothing
  (Just (Identity a), Nothing) -> Just $ This a
  (Nothing, Just (Identity b)) -> Just $ That b
  (Just (Identity a), Just (Identity b)) -> Just $ These a b

-- | Tag type for 'Either' to use it as a 'DSum'.
data EitherTag l r a where
  LeftTag :: EitherTag l r l
  RightTag :: EitherTag l r r
  deriving (Typeable)

deriving instance Show (EitherTag l r a)
deriving instance Eq (EitherTag l r a)
deriving instance Ord (EitherTag l r a)

instance {-# INCOHERENT #-} (Show (f l), Show (f r)) => ShowTag (EitherTag l r) f where
  showTagToShow e _ = case e of
    LeftTag -> id
    RightTag -> id

instance {-# INCOHERENT #-} (Eq (f l), Eq (f r)) => EqTag (EitherTag l r) f where
  eqTagToEq e _ = case e of
    LeftTag -> id
    RightTag -> id

instance GEq (EitherTag l r) where
  geqToEq _ = id
  geqUnify LeftTag LeftTag _ same = same
  geqUnify RightTag RightTag _ same = same
  geqUnify _ _ unknown _ = unknown
  geq a b = case (a, b) of
    (LeftTag, LeftTag) -> Just Refl
    (RightTag, RightTag) -> Just Refl
    _ -> Nothing

instance GCompare (EitherTag l r) where
  gcompareToOrd _ = id
  gcompare a b = case (a, b) of
    (LeftTag, LeftTag) -> GEQ
    (LeftTag, RightTag) -> GLT
    (RightTag, LeftTag) -> GGT
    (RightTag, RightTag) -> GEQ

instance {-# INCOHERENT #-} GShow (EitherTag l r) where
  gshowToShow _ = id

instance (Show l, Show r) => ShowTag (EitherTag l r) Identity where
  showTagToShow t _ = case t of
    LeftTag -> id
    RightTag -> id

-- | Convert 'Either' to a 'DSum'. Inverse of 'dsumToEither'.
eitherToDSum :: Either a b -> DSum (EitherTag a b) Identity
eitherToDSum = \case
  Left a -> (LeftTag :=> Identity a)
  Right b -> (RightTag :=> Identity b)

-- | Convert 'DSum' to 'Either'. Inverse of 'eitherToDSum'.
dsumToEither :: DSum (EitherTag a b) Identity -> Either a b
dsumToEither = \case
  (LeftTag :=> Identity a) -> Left a
  (RightTag :=> Identity b) -> Right b

--------------------------------------------------------------------------------
-- ComposeMaybe
--------------------------------------------------------------------------------

-- | We can't use @Compose Maybe@ instead of 'ComposeMaybe', because that would
-- make the 'f' parameter have a nominal type role.  We need f to be
-- representational so that we can use safe 'coerce'.
newtype ComposeMaybe f a = ComposeMaybe { getComposeMaybe :: Maybe (f a) } deriving (Show, Eq, Ord)

instance EqTag f g => EqTag f (ComposeMaybe g) where
  eqTagToEq f _ = eqTagToEq f (Proxy :: Proxy g)

deriving instance Functor f => Functor (ComposeMaybe f)

instance {-# INCOHERENT #-} GShow k => ShowTag k (ComposeMaybe k) where
  showTagToShow k _ r = gshowToShow k (showTagToShow k (Proxy :: Proxy k) r)

--------------------------------------------------------------------------------
-- Deprecated functions
--------------------------------------------------------------------------------

{-# INLINE sequenceDmap #-}
{-# DEPRECATED sequenceDmap "Use 'Data.Dependent.Map.traverseWithKey (\\_ -> fmap Identity)' instead" #-}
-- | Run the actions contained in the 'DMap'
sequenceDmap :: Applicative t => DMap f t -> t (DMap f Identity)
sequenceDmap = DMap.traverseWithKey $ \_ t -> Identity <$> t

{-# DEPRECATED wrapDMap "Use 'Data.Dependent.Map.map (f . runIdentity)' instead" #-}
-- | Replace the 'Identity' functor for a 'DMap''s values with a different functor
wrapDMap :: (forall a. a -> f a) -> DMap k Identity -> DMap k f
wrapDMap f = DMap.map $ f . runIdentity

{-# DEPRECATED rewrapDMap "Use 'Data.Dependent.Map.map' instead" #-}
-- | Replace one functor for a 'DMap''s values with a different functor
rewrapDMap :: (forall (a :: *). f a -> g a) -> DMap k f -> DMap k g
rewrapDMap = DMap.map

{-# DEPRECATED unwrapDMap "Use 'Data.Dependent.Map.map (Identity . f)' instead" #-}
-- | Replace one functor for a 'DMap''s values with the 'Identity' functor
unwrapDMap :: (forall a. f a -> a) -> DMap k f -> DMap k Identity
unwrapDMap f = DMap.map $ Identity . f

{-# DEPRECATED unwrapDMapMaybe "Use 'Data.Dependent.Map.mapMaybeWithKey (\\_ a -> fmap Identity $ f a)' instead" #-}
-- | Like 'unwrapDMap', but possibly delete some values from the DMap
unwrapDMapMaybe :: GCompare k => (forall a. f a -> Maybe a) -> DMap k f -> DMap k Identity
unwrapDMapMaybe f = DMap.mapMaybeWithKey $ \_ a -> Identity <$> f a

{-# DEPRECATED extractFunctorDMap "Use 'mapKeyValuePairsMonotonic (\\(Const2 k :=> Identity v) -> Const2 k :=> v)' instead" #-}
-- | Eliminate the 'Identity' functor in a 'DMap' and replace it with the
-- underlying functor
extractFunctorDMap :: DMap (Const2 k (f v)) Identity -> DMap (Const2 k v) f
extractFunctorDMap = mapKeyValuePairsMonotonic $ \(Const2 k :=> Identity v) -> Const2 k :=> v
