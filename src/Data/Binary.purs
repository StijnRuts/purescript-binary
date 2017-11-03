module Data.Binary
  ( Bit(..)
  , bitToChar
  , charToBit
  , Bits(..)
  , lsb
  , msb
  , isNegative
  , complement
  , head
  , tail
  , init
  , last
  , drop
  , take
  , uncons
  , length
  , align
  , diffBits
  , class Binary
  , class Fixed
  , diffFixed
  , modAdd
  , modMul
  , class FitsInt
  , _0
  , _1
  , isOdd
  , isEven
  , and
  , xor
  , or
  , invert
  , add'
  , add
  , unsafeAdd
  , leftShift
  , unsafeLeftShift
  , rightShift
  , signedRightShift
  , unsafeRightShift
  , toBinString
  , tryFromBinString
  , toInt
  , tryToInt
  , tryFromInt
  , toBits
  , tryFromBits
  , numBits
  , class Elastic
  , fromBits
  , extendOverflow
  , addLeadingZeros
  , stripLeadingZeros
  , extendAdd
  , tryFromBinStringElastic
  , fromInt
  , half
  , double
  , diffElastic
  , divMod
  , multiply
  , toStringAs
  , Radix
  , bin
  , oct
  , dec
  , hex
  ) where

import Conditional (ifelse)
import Control.Plus (empty)
import Data.Array (singleton, (!!))
import Data.Array as A
import Data.Bifunctor (bimap)
import Data.Binary.Overflow (Overflow(..), discardOverflow)
import Data.Int (odd)
import Data.Int.Bits as Int
import Data.Maybe (Maybe(Nothing, Just), fromMaybe, fromMaybe')
import Data.Newtype (class Newtype, unwrap, wrap)
import Data.String as Str
import Data.Traversable (traverse)
import Data.Tuple (Tuple(Tuple), uncurry)
import Data.Tuple.Nested (get1)
import Partial.Unsafe (unsafeCrashWith)
import Prelude hiding (add)
import Type.Proxy (Proxy(Proxy))


newtype Bit = Bit Boolean
derive instance newtypeBit :: Newtype Bit _
derive newtype instance eqBit :: Eq Bit
derive newtype instance ordBit :: Ord Bit
derive newtype instance heytingAlgebraBit :: HeytingAlgebra Bit
derive newtype instance booleanAlgebraBit :: BooleanAlgebra Bit
derive newtype instance boundedBit :: Bounded Bit

instance showBit :: Show Bit where
  show = bitToChar >>> singleton >>> Str.fromCharArray

charToBit :: Char -> Maybe Bit
charToBit '1' = Just (Bit true)
charToBit '0' = Just (Bit false)
charToBit _   = Nothing

bitToChar :: Bit -> Char
bitToChar (Bit true)  = '1'
bitToChar (Bit false) = '0'

intToBit :: Int -> Bit
intToBit 1 = _1
intToBit _ = _0

newtype Bits = Bits (Array Bit)
derive instance newtypeBits :: Newtype Bits _
derive newtype instance eqBits :: Eq Bits
derive newtype instance showBits :: Show Bits
derive newtype instance semigroupBits :: Semigroup Bits

instance ordBits :: Ord Bits where
  compare a b = f (isNegative a) (isNegative b) where
    f true true = cmp
    f false false = cmp
    f true false = LT
    f false true = GT
    cmp = uncurry compare $ bimap unwrap unwrap $ align a b

instance semiringBits :: Semiring Bits where
  zero = _0
  add = extendAdd
  one = _1
  mul = multiply

instance ringBits :: Ring Bits where
  sub = diffElastic

complement :: Bits -> Bits
complement = invert >>> unsafeAdd _1

-- | align length by adding zeroes from the left
align :: Bits -> Bits -> Tuple Bits Bits
align bas@(Bits as) bbs@(Bits bs) =
  case compare la lb of
  EQ -> Tuple bas bbs
  LT -> Tuple (extend (lb - la) as) bbs
  GT -> Tuple bas (extend (la - lb) bs)
  where la = A.length as
        lb = A.length bs
        extend :: Int -> Array Bit -> Bits
        extend d xs = Bits (A.replicate d _0 <> xs)

head :: Bits -> Bit
head (Bits bits) = fromMaybe _0 (A.head bits)

tail :: Bits -> Bits
tail (Bits bits) = defaultBits (A.tail bits)

init :: Bits -> Bits
init (Bits bits) = defaultBits (A.init bits)

last :: Bits -> Bit
last (Bits bits) = fromMaybe _0 (A.last bits)

drop :: Int -> Bits -> Bits
drop n (Bits bits) =
  let xs = A.drop n bits
  in if A.null xs then _0 else Bits xs

take :: Int -> Bits -> Bits
take n (Bits bits) =
  let xs = A.take n bits
  in if A.null xs then _0 else Bits xs

uncons :: Bits -> { head :: Bit, tail :: Bits }
uncons (Bits bits) = f (A.uncons bits) where
  f (Just { head: h, tail: t }) = { head: h, tail: Bits t }
  f Nothing = { head: _0, tail: _0 }

length :: Bits -> Int
length = unwrap >>> A.length

defaultBits :: Maybe (Array Bit) -> Bits
defaultBits (Just []) = _0
defaultBits (Just a) = Bits a
defaultBits Nothing = _0

class Ord a <= Binary a where
  _0 :: a
  _1 :: a
  -- | Least significant bit
  lsb :: a -> Bit
  -- | most significant bit
  msb :: a -> Bit
  and :: a -> a -> a
  xor :: a -> a -> a
  or :: a -> a -> a
  invert :: a -> a
  add' :: Bit -> a -> a -> Overflow Bit a
  leftShift :: Bit -> a -> Overflow Bit a
  rightShift :: Bit -> a -> Overflow Bit a
  signedRightShift :: a -> Overflow Bit a
  toBits :: a -> Bits

instance binaryInt :: Binary Int where
  _0 = 0
  _1 = 1
  lsb i = intToBit $ Int.and i 1
  msb i = intToBit $ Int.zshr i 31
  and = Int.and
  xor = Int.xor
  or = Int.or
  invert = Int.xor top
  add' bit a b = unsafeFixedFromBits <$> add' bit (toBits a) (toBits b)
  leftShift (Bit b) i = Overflow (msb i) res where
    res = ifelse b 1 0 `or` Int.shl i 1
  rightShift (Bit b) i = Overflow (lsb i) res where
    res = ifelse b bottom 0 `or` Int.shr i 1
  signedRightShift i = rightShift (intToBit $ Int.and bottom i) i
  toBits i | i == bottom = Bits (A.cons _1 (A.replicate 31 _0))
  toBits i =
    if i < zero
    then complement $ Bits (bits (- i))
    else Bits (bits i)
    where
    bits = intBits >>> addLeadingZerosArray 32
    intBits 0 = [_0]
    intBits n | odd n     = A.snoc (intBits (n `div` 2)) _1
              | otherwise = A.snoc (intBits (n `div` 2)) _0


instance binaryBit :: Binary Bit where
  _0 = Bit false
  _1 = Bit true
  lsb = id
  msb = id
  and (Bit a) (Bit b) = Bit (a && b)
  xor (Bit a) (Bit b) = Bit ((a || b) && not (a && b))
  or (Bit a) (Bit b) = Bit (a || b)
  invert (Bit b) = Bit (not b)
  add' (Bit false) (Bit false) (Bit false) = Overflow _0 _0
  add' (Bit false) (Bit false) (Bit true)  = Overflow _0 _1
  add' (Bit false) (Bit true) (Bit false)  = Overflow _0 _1
  add' (Bit false) (Bit true) (Bit true)   = Overflow _1 _0
  add' (Bit true) (Bit false) (Bit false)  = Overflow _0 _1
  add' (Bit true) (Bit false) (Bit true)   = Overflow _1 _0
  add' (Bit true) (Bit true) (Bit false)   = Overflow _1 _0
  add' (Bit true) (Bit true) (Bit true)    = Overflow _1 _1
  toBits = A.singleton >>> Bits
  leftShift b a = Overflow a b
  rightShift b a = Overflow a b
  signedRightShift a = Overflow a a

instance binaryBits :: Binary Bits where
  _0 = Bits (pure _0)
  _1 = Bits (pure _1)
  lsb (Bits as) = fromMaybe _0 (A.last as)
  msb (Bits as) = fromMaybe _0 (A.head as)
  and (Bits as) (Bits bs) = Bits (A.zipWith and as bs)
  xor (Bits as) (Bits bs) = Bits (A.zipWith xor as bs)
  or (Bits as) (Bits bs) = Bits (A.zipWith or as bs)
  invert (Bits bits) = Bits (map invert bits)
  add' bit abits@(Bits as) bbits@(Bits bs) =
    Bits <$> A.foldr f acc pairs where
      f (Tuple a b) (Overflow o t) = flip A.cons t <$> add' o a b
      acc = Overflow bit empty
      pairs = uncurry A.zip $ bimap unwrap unwrap $ align abits bbits
  leftShift bit (Bits bits) = Bits <$> A.foldr f (Overflow bit []) bits
    where f a (Overflow o t) = flip A.cons t <$> leftShift o a
  rightShift bit (Bits bits) = Bits <$> A.foldl f (Overflow bit []) bits
    where f (Overflow o t) a = A.snoc t <$> rightShift o a
  signedRightShift bits = rightShift (msb bits) bits
  toBits = id

isNegative :: ∀ a. Binary a => a -> Boolean
isNegative = msb >>> eq _1

nonNegative :: ∀ a. Binary a => a -> Boolean
nonNegative = not isNegative

isOdd :: ∀ a. Binary a => a -> Boolean
isOdd = lsb >>> eq _1

isEven :: ∀ a. Binary a => a -> Boolean
isEven = lsb >>> eq _0

toBinString :: ∀ a. Binary a => a -> String
toBinString = toBits
          >>> unwrap
          >>> map bitToChar
          >>> Str.fromCharArray

tryFromBinString :: ∀ a. Fixed a => String -> Maybe a
tryFromBinString = Str.toCharArray
               >>> traverse charToBit
               >=> Bits
               >>> tryFromBits

half :: ∀ a. Binary a => a -> a
-- | https://en.wikipedia.org/wiki/Arithmetic_shift#Non-equivalence_of_arithmetic_right_shift_and_division
half a | isNegative a && isOdd a = half (unsafeAdd a _1)
half a= signedRightShift a # discardOverflow

diffBits :: Bits -> Bits -> Bits
diffBits a b | a == b = Bits $ A.replicate (max (length a) (length b)) _0
diffBits a b | a < b = diffBits b a
diffBits a b = Bits acc where
  f :: (Tuple Bit Bit) -> Tuple Boolean (Array Bit) -> Tuple Boolean (Array Bit)
  -- https://i.stack.imgur.com/5M40R.jpg
  f (Tuple (Bit false) (Bit false)) (Tuple false acc) = Tuple false (A.cons _0 acc)
  f (Tuple (Bit false) (Bit false)) (Tuple true  acc) = Tuple true  (A.cons _1 acc)
  f (Tuple (Bit false) (Bit true) ) (Tuple false acc) = Tuple true  (A.cons _1 acc)
  f (Tuple (Bit false) (Bit true) ) (Tuple true  acc) = Tuple true  (A.cons _0 acc)
  f (Tuple (Bit true)  (Bit false)) (Tuple false acc) = Tuple false (A.cons _1 acc)
  f (Tuple (Bit true)  (Bit false)) (Tuple true  acc) = Tuple false (A.cons _0 acc)
  f (Tuple (Bit true)  (Bit true) ) (Tuple false acc) = Tuple false (A.cons _0 acc)
  f (Tuple (Bit true)  (Bit true) ) (Tuple true  acc) = Tuple true  (A.cons _1 acc)
  pairs = uncurry A.zip $ bimap unwrap unwrap $ align a b
  (Tuple _ acc) = A.foldr f (Tuple false []) pairs


class Binary a <= FitsInt a where
  toInt :: a -> Int

instance intFitsInt :: FitsInt Int where
  toInt = id

class (Bounded a, Binary a) <= Fixed a where
  numBits :: Proxy a -> Int
  tryFromInt :: Int -> Maybe a
  tryFromBits :: Bits -> Maybe a

instance fixedInt :: Fixed Int where
  numBits _ = 32
  tryFromInt = Just
  tryFromBits bits =
    if isNegative bits
    then map negate $ bitsToInt $ complement $ bits
    else bitsToInt $ tail bits
    where
    bitsToInt :: Bits -> Maybe Int
    bitsToInt (Bits bs) = Just $ get1 $ A.foldr f (Tuple 0 1) bs
    f b (Tuple r p) = Tuple (p * toInt b + r) (p * 2)

tryToInt :: ∀ a. Binary a => a -> Maybe Int
tryToInt binary | bits <- toBits binary = tryFromBits bits

modAdd :: ∀ a. Fixed a => a -> a -> a
modAdd a b = unsafeFixedFromBits result where
  nBits = numBits (Proxy :: Proxy a)
  result = mkBits (add (toBits a) (toBits b))
  numValues = _1 <> Bits (A.replicate nBits _0)
  mkBits (Overflow (Bit false) bits) = bits
  mkBits res = tail $ diffBits (extendOverflow res) numValues

modMul :: ∀ a. Fixed a => a -> a -> a
modMul a b = unsafeFixedFromBits result where
  nBits = numBits (Proxy :: Proxy a)
  rawResult = multiply (toBits a) (toBits b)
  numValues = _1 <> Bits (A.replicate nBits _0)
  t@(Tuple quo rem) = divMod rawResult numValues
  result = if isOdd quo then tail rem else rem

diffFixed :: ∀ a. Fixed a => a -> a -> a
diffFixed a b = unsafeFixedFromBits $ diffBits (toBits a) (toBits b) -- safe, as diff is always less than operands

unsafeFixedFromBits :: ∀ a. Fixed a => Bits -> a
unsafeFixedFromBits bits = fromMaybe' (\_ -> unsafeCrashWith err) (tryFromBits bits) where
  err = "Unsafe conversion of Bits to a Fixed value has failed: " <> show bits

instance fixedBit :: Fixed Bit where
  numBits _ = 1

  tryFromInt 0 = Just _0
  tryFromInt 1 = Just _1
  tryFromInt _ = Nothing

  tryFromBits (Bits [b]) = Just b
  tryFromBits _ = Nothing

instance fitsIntBit :: FitsInt Bit where
  toInt (Bit true)  = 1
  toInt (Bit false) = 0

-- | Unsigned binary addition
-- | Returns overflow bit
add :: ∀ a. Binary a => a -> a -> Overflow Bit a
add = add' _0

-- | Unsigned binary addition
-- | Discards overflow bit
unsafeAdd :: ∀ a. Binary a => a -> a -> a
unsafeAdd a1 a2 = discardOverflow (add a1 a2)

unsafeRightShift :: ∀ a. Binary a => a -> a
unsafeRightShift a = discardOverflow (rightShift _0 a)

unsafeLeftShift :: ∀ a. Binary a => a -> a
unsafeLeftShift a = discardOverflow (leftShift _0 a)



class Binary a <= Elastic a where
  fromBits :: Bits -> a
  extendOverflow :: Overflow Bit a -> a

instance elasticBits :: Elastic Bits where
  fromBits (Bits []) = _0
  fromBits bs = bs
  extendOverflow (Overflow (Bit false) bits) = bits
  extendOverflow (Overflow bit (Bits bits)) = Bits $ A.cons bit bits

addLeadingZeros :: ∀ a. Elastic a => Int -> a -> a
addLeadingZeros w = toBits
                >>> unwrap
                >>> addLeadingZerosArray w
                >>> wrap
                >>> fromBits

addLeadingZerosArray :: Int -> Array Bit -> Array Bit
addLeadingZerosArray width bits =
  let d = sub width (A.length bits)
  in if d < 1 then bits else (A.replicate d _0) <> bits

stripLeadingZeros :: ∀ a. Elastic a => a -> a
stripLeadingZeros = toBits
                >>> unwrap
                >>> stripLeadingZerosArray
                >>> wrap
                >>> fromBits

stripLeadingZerosArray :: Array Bit -> Array Bit
stripLeadingZerosArray bits =
  let xs = A.dropWhile (eq _0) bits
  in if A.null xs then [_0] else xs

extendAdd :: ∀ a. Elastic a => a -> a -> a
extendAdd a b = extendOverflow (add a b)

tryFromBinStringElastic :: ∀ a. Elastic a => String -> Maybe a
tryFromBinStringElastic =
  Str.toCharArray >>> traverse charToBit >>> map wrap >>> map fromBits

fromInt :: ∀ a. Elastic a => Int -> a
fromInt = toBits >>> fromBits

double :: ∀ a. Elastic a => a -> a
double = leftShift _0 >>> extendOverflow

diffElastic :: ∀ a. Elastic a => a -> a -> a
diffElastic a b = fromBits $ diffBits (toBits a) (toBits b)

divMod :: ∀ a. Elastic a => a -> a -> Tuple a a
divMod x _ | x == _0 = Tuple _0 _0
divMod x y = if r' >= y
             then Tuple (inc q) (r' `diffElastic` y)
             else Tuple q r'
  where
    t = divMod (half x) y
    (Tuple q r) = bimap double double t
    r' = if isOdd x then inc r else r
    inc a = extendAdd a _1

multiply :: ∀ a. Elastic a => a -> a -> a
multiply x _ | x == _0 = _0
multiply _ y | y == _0 = _0
multiply x y = let z = multiply x (half y)
               in if isEven y then double z
                              else extendAdd x (double z)

-- | The number of unique digits (including zero) used to represent integers in
-- | a specific base.
newtype Radix = Radix Bits

derive newtype instance eqRadix :: Eq Radix
derive newtype instance showRadix :: Show Radix
derive newtype instance ordRadix :: Ord Radix

-- | The base-2 system.
bin :: Radix
bin = Radix (toBits 2)

-- | The base-8 system.
oct :: Radix
oct = Radix (toBits 8)

-- | The base-10 system.
dec :: Radix
dec = Radix (toBits 10)

-- | The base-16 system.
hex :: Radix
hex = Radix (toBits 16)

toStringAs :: ∀ a. Binary a => Radix -> a -> String
toStringAs (Radix r) b = Str.fromCharArray (req (toBits b) []) where
  req bits acc | bits < r = bitsAsChar bits <> acc
  req bits acc =
    let (Tuple quo rem) = bits `divMod` r
    in req quo (bitsAsChar rem <> acc)

-- TODO: fromStringAs

bitsAsChar :: Bits -> Array Char
bitsAsChar bits = fromMaybe [] do
  i <- tryToInt bits
  c <- ['0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f'] !! i
  pure [c]
