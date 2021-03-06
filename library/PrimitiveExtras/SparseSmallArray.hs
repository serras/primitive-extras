module PrimitiveExtras.SparseSmallArray
(
  SparseSmallArray,
  empty,
  singleton,
  maybeList,
  pair,
  insert,
  replace,
  unset,
  lookup,
  focusAt,
  toMaybeList,
  toIndexedList,
  elementsUnfoldl,
  elementsUnfoldlM,
  elementsListT,
  onElementAtFocus,
  null,
)
where

import PrimitiveExtras.Prelude hiding (lookup, empty, insert, null)
import PrimitiveExtras.Types
import qualified PrimitiveExtras.Prelude as Prelude
import qualified PrimitiveExtras.Bitmap as Bitmap
import qualified PrimitiveExtras.SmallArray as SmallArray
import qualified Focus
import qualified Control.Foldl as Foldl


instance Show a => Show (SparseSmallArray a) where
  show = show . toMaybeList

deriving instance Eq a => Eq (SparseSmallArray a)

instance Foldable SparseSmallArray where
  {-# INLINE foldr #-}
  foldr step state = foldr step state . elementsUnfoldl
  {-# INLINE foldl' #-}
  foldl' step state = foldl' step state . elementsUnfoldl
  {-# INLINE foldMap #-}
  foldMap monoid = foldMap monoid . elementsUnfoldl

{-# INLINE empty #-}
empty :: SparseSmallArray e
empty = SparseSmallArray Bitmap.empty Prelude.empty

-- |
-- An array with a single element at the specified index.
{-# INLINE singleton #-}
singleton :: Int -> e -> SparseSmallArray e
singleton i e = 
  let b = Bitmap.singleton i
      a = runST $ newSmallArray 1 e >>= unsafeFreezeSmallArray
      in SparseSmallArray b a

{-# INLINE pair #-}
pair :: Int -> e -> Int -> e -> SparseSmallArray e
pair i1 e1 i2 e2 =
  {-# SCC "pair" #-} 
  SparseSmallArray bitmap array
  where 
    bitmap = Bitmap.pair i1 i2
    array = SmallArray.orderedPair i1 e1 i2 e2

{-# INLINE maybeList #-}
maybeList :: [Maybe e] -> SparseSmallArray e
maybeList list =
  SparseSmallArray (Bitmap.boolList (map isJust list)) (SmallArray.list (catMaybes list))

{-|
Insert an element value at the index.
It's your obligation to ensure that the index is empty before the operation.
-}
{-# INLINE insert #-}
insert :: Int -> e -> SparseSmallArray e -> SparseSmallArray e
insert i e (SparseSmallArray b a) =
  {-# SCC "insert" #-} 
  let
    sparseIndex = Bitmap.populatedIndex i b
    in SparseSmallArray (Bitmap.insert i b) (SmallArray.insert sparseIndex e a)
    
{-# INLINE replace #-}
replace :: Int -> e -> SparseSmallArray e -> SparseSmallArray e
replace i e (SparseSmallArray b a) =
  {-# SCC "replace" #-} 
  let
    sparseIndex = Bitmap.populatedIndex i b
    in SparseSmallArray b (SmallArray.set sparseIndex e a)

-- |
-- Remove an element.
{-# INLINE unset #-}
unset :: Int -> SparseSmallArray e -> SparseSmallArray e
unset i (SparseSmallArray b a) =
  {-# SCC "unset" #-}
  if Bitmap.isPopulated i b
    then
      let
        sparseIndex = Bitmap.populatedIndex i b
        b' = Bitmap.invert i b
        a' = SmallArray.unset sparseIndex a
        in SparseSmallArray b' a'
    else SparseSmallArray b a

-- |
-- Lookup an item at the index.
{-# INLINE lookup #-}
lookup :: Int -> SparseSmallArray e -> Maybe e
lookup i (SparseSmallArray b a) =
  {-# SCC "lookup" #-} 
  if Bitmap.isPopulated i b
    then Just (indexSmallArray a (Bitmap.populatedIndex i b))
    else Nothing

-- |
-- Convert into a list representation.
{-# INLINE toMaybeList #-}
toMaybeList :: SparseSmallArray e -> [Maybe e]
toMaybeList ssa = do
  i <- Bitmap.allBitsList
  return (lookup i ssa)

{-# INLINE toIndexedList #-}
toIndexedList :: SparseSmallArray e -> [(Int, e)]
toIndexedList = catMaybes . zipWith (\i -> fmap (i,)) [0..] . toMaybeList

{-# INLINE elementsUnfoldl #-}
elementsUnfoldl :: SparseSmallArray e -> Unfoldl e
elementsUnfoldl (SparseSmallArray _ array) = Unfoldl (\ f z -> foldl' f z array)

{-# INLINE elementsUnfoldlM #-}
elementsUnfoldlM :: Monad m => SparseSmallArray a -> UnfoldlM m a
elementsUnfoldlM (SparseSmallArray _ array) = SmallArray.elementsUnfoldlM array

{-# INLINE elementsListT #-}
elementsListT :: SparseSmallArray a -> ListT STM a
elementsListT (SparseSmallArray _ array) = SmallArray.elementsListT array

{-# INLINE onElementAtFocus #-}
onElementAtFocus :: Monad m => Int -> Focus a m b -> Focus (SparseSmallArray a) m b
onElementAtFocus index (Focus concealA revealA) = Focus concealSsa revealSsa where
  concealSsa = fmap (fmap aChangeToSsaChange) concealA where
    aChangeToSsaChange = \ case
      Focus.Leave -> Focus.Leave
      Focus.Set a -> Focus.Set (SparseSmallArray (Bitmap.singleton index) (pure a))
      Focus.Remove -> Focus.Leave
  revealSsa (SparseSmallArray indices array) =
    fmap (fmap aChangeToSsaChange) $
    if Bitmap.isPopulated index indices 
      then do
        a <- indexSmallArrayM array (Bitmap.populatedIndex index indices)
        revealA a
      else concealA
    where
      sparseIndex = Bitmap.populatedIndex index indices
      aChangeToSsaChange = \ case
        Focus.Leave -> Focus.Leave
        Focus.Set a -> if Bitmap.isPopulated index indices
          then let
            newArray = SmallArray.set sparseIndex a array
            in Focus.Set (SparseSmallArray indices newArray)
          else let
            newIndices = Bitmap.insert index indices
            newArray = SmallArray.insert sparseIndex a array
            in Focus.Set (SparseSmallArray newIndices newArray)
        Focus.Remove -> let
          newIndices = Bitmap.invert index indices
          in if Bitmap.null newIndices
            then Focus.Remove
            else let
              newArray = SmallArray.unset sparseIndex array
              in Focus.Set (SparseSmallArray newIndices newArray)

{-# INLINE focusAt #-}
focusAt :: Monad m => Focus a m b -> Int -> SparseSmallArray a -> m (b, SparseSmallArray a)
focusAt aFocus index = case onElementAtFocus index aFocus of
  Focus conceal reveal -> \ ssa -> do
    (b, change) <- reveal ssa
    return $ (b,) $ case change of
      Focus.Leave -> ssa
      Focus.Set newSsa -> newSsa
      Focus.Remove -> empty

{-# INLINE null #-}
null :: SparseSmallArray a -> Bool
null (SparseSmallArray bm _) = Bitmap.null bm
