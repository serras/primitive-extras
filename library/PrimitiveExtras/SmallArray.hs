module PrimitiveExtras.SmallArray
where

import PrimitiveExtras.Prelude
import PrimitiveExtras.Types
import GHC.Exts hiding (toList)
import qualified Focus


{-# INLINE empty #-}
empty :: SmallArray a
empty = runSmallArray (newSmallArray 0 undefined)

{-| A workaround for the weird forcing of 'undefined' values int 'newSmallArray' -}
{-# INLINE newEmptySmallArray #-}
newEmptySmallArray :: PrimMonad m => Int -> m (SmallMutableArray (PrimState m) a)
newEmptySmallArray size = newSmallArray size (unsafeCoerce 0)

{-# INLINE list #-}
list :: [a] -> SmallArray a
list list =
  let
    !size = length list
    in runSmallArray $ do
      m <- newEmptySmallArray size
      let populate index list = case list of
            element : list -> do
              writeSmallArray m index element
              populate (succ index) list
            [] -> return m
          in populate 0 list

-- |
-- Remove an element.
{-# INLINE unset #-}
unset :: Int -> SmallArray a -> SmallArray a
unset index array =
  {-# SCC "unset" #-}
  let !size = sizeofSmallArray array
      !newSize = pred size
      !newIndex = succ index
      !amountOfFollowingElements = size - newIndex
      in runSmallArray $ do
        newMa <- newSmallArray newSize undefined
        copySmallArray newMa 0 array 0 index
        copySmallArray newMa index array newIndex amountOfFollowingElements
        return newMa

{-# INLINE set #-}
set :: Int -> a -> SmallArray a -> SmallArray a
set index a array =
  {-# SCC "set" #-} 
  let
    !size = sizeofSmallArray array
    in runSmallArray $ do
      newMa <- newSmallArray size undefined
      copySmallArray newMa 0 array 0 size
      writeSmallArray newMa index a
      return newMa

{-# INLINE insert #-}
insert :: Int -> a -> SmallArray a -> SmallArray a
insert index a array =
  {-# SCC "insert" #-} 
  let
    !size = sizeofSmallArray array
    !newSize = succ size
    !nextIndex = succ index
    !amountOfFollowingElements = size - index
    in runSmallArray $ do
      newMa <- newSmallArray newSize a
      copySmallArray newMa 0 array 0 index
      copySmallArray newMa nextIndex array index amountOfFollowingElements
      return newMa

{-# INLINE cons #-}
cons :: a -> SmallArray a -> SmallArray a
cons a array =
  {-# SCC "cons" #-} 
  let
    size = sizeofSmallArray array
    newSize = succ size
    in runSmallArray $ do
      newMa <- newSmallArray newSize a
      copySmallArray newMa 1 array 0 size
      return newMa

{-# INLINABLE orderedPair #-}
orderedPair :: Int -> e -> Int -> e -> SmallArray e
orderedPair i1 e1 i2 e2 =
  {-# SCC "orderedPair" #-} 
  runSmallArray $ if 
    | i1 < i2 -> do
      a <- newSmallArray 2 e1
      writeSmallArray a 1 e2
      return a
    | i1 > i2 -> do
      a <- newSmallArray 2 e1
      writeSmallArray a 0 e2
      return a
    | otherwise -> do
      a <- newSmallArray 1 e2
      return a

{-# INLINE find #-}
find :: (a -> Bool) -> SmallArray a -> Maybe a
find test array =
  {-# SCC "find" #-} 
  let
    !size = sizeofSmallArray array
    iterate index = if index < size
      then let
        element = indexSmallArray array index
        in if test element
          then Just element
          else iterate (succ index)
      else Nothing
    in iterate 0

{-# INLINE findWithIndex #-}
findWithIndex :: (a -> Bool) -> SmallArray a -> Maybe (Int, a)
findWithIndex test array =
  {-# SCC "findWithIndex" #-} 
  let
    !size = sizeofSmallArray array
    iterate index = if index < size
      then let
        element = indexSmallArray array index
        in if test element
          then Just (index, element)
          else iterate (succ index)
      else Nothing
    in iterate 0

{-# INLINABLE elementsUnfoldM #-}
elementsUnfoldM :: Monad m => SmallArray e -> UnfoldM m e
elementsUnfoldM array = UnfoldM $ \ step initialState -> let
  !size = sizeofSmallArray array
  iterate index !state = if index < size
    then do
      element <- indexSmallArrayM array index
      newState <- step state element
      iterate (succ index) newState
    else return state
  in iterate 0 initialState

{-# INLINABLE onFoundElementFocus #-}
onFoundElementFocus :: (Monad m, Eq a) => (a -> Bool) -> Focus a m b -> Focus (SmallArray a) m b
onFoundElementFocus testA (Focus concealA revealA) = Focus concealArray revealArray where
  concealArray = fmap (fmap arrayChange) concealA where
    arrayChange = \ case
      Focus.Set newValue -> Focus.Set (pure newValue)
      _ -> Focus.Leave
  revealArray array = case findWithIndex testA array of
    Just (index, value) -> fmap (fmap arrayChange) (revealA value) where
      arrayChange = \ case
        Focus.Leave -> Focus.Leave
        Focus.Set newValue -> if newValue == value
          then Focus.Leave
          else Focus.Set (set index newValue array)
        Focus.Remove -> if sizeofSmallArray array > 1
          then Focus.Set (unset index array)
          else Focus.Remove
    Nothing -> fmap (fmap arrayChange) concealA where
      arrayChange = \ case
        Focus.Set newValue -> Focus.Set (cons newValue array)
        _ -> Focus.Leave

toList :: forall a. SmallArray a -> [a]
toList array = PrimitiveExtras.Prelude.toList (elementsUnfoldM array :: UnfoldM Identity a)
