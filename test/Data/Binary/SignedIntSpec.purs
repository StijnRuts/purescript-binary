module Data.Binary.SignedInt.Spec
  ( spec
  ) where

import Prelude

import Control.Monad.Eff.Console (CONSOLE)
import Control.Monad.Eff.Random (RANDOM)
import Data.Array (foldr, replicate)
import Data.Array as A
import Data.Binary as Bin
import Data.Binary.BaseN (Radix(..), toStringAs)
import Data.Binary.SignedInt (SignedInt, fromInt, toInt, toNumberAs)
import Data.Foldable (all)
import Data.Int as Int
import Data.List (List(..), (:))
import Data.Newtype (unwrap)
import Data.String as Str
import Data.Typelevel.Num (class GtEq, class Pos, D32, d32, d99)
import Imul (imul)
import Test.Arbitrary (ArbInt(..), ArbSemiringOp(..), ArbSignedInt32(ArbSignedInt32))
import Test.QuickCheck (Result, (<?>), (===))
import Test.Unit (TestSuite, suite, test)
import Test.Unit.QuickCheck (quickCheck)

spec :: ∀ e. TestSuite (random :: RANDOM, console :: CONSOLE | e)
spec = suite "SignedInt" do
  test "number of bits" $ quickCheck propNumberOfBits
  test "fromInt" $ quickCheck (propFromInt d32)
  test "fromInt" $ quickCheck (propFromInt d99)
  test "number of bits is 32" $ quickCheck propBitSize
  test "negation" $ quickCheck propNegation
  test "propIntRoundtrip" $ quickCheck propIntRoundtrip
  test "toBinString contains only bin digits" $ quickCheck propBinString
  test "toBinString isn't empty" $ quickCheck propBinStringEmptiness
  test "toBinString produces unique representation" $ quickCheck propBinStringUniqness
  test "addition" $ quickCheck propAddition
  test "multiplication" $ quickCheck propMultiplication

propNumberOfBits :: List ArbSignedInt32 ->
                    List (ArbSemiringOp (SignedInt D32)) ->
                    Result
propNumberOfBits ints ops =
  expected == actual
    <?> "\nExpected:  " <> show expected
    <>  "\nActual:    " <> show actual
    <>  "\nInts:      " <> show ints
    <>  "\nOps:       " <> show ops
    <>  "\nRes:       " <> show res
  where
    expected = 32
    actual = Bin.length $ Bin.toBits res
    res = r ints ops zero
    r Nil _ a = a
    r _ Nil a = a
    r ((ArbSignedInt32 i):is) ((ArbSemiringOp _ o):os) a = r is os (i `o` a)


propFromInt :: ∀ b . Pos b => GtEq b D32 => b -> ArbInt -> Result
propFromInt b (ArbInt i) =
  expected == actual
    <?> "\nExpected:  " <> show expected
    <>  "\nActual:    " <> show actual
    <>  "\nInt:       " <> show i
    <>  "\nSignedInt: " <> show si
  where
    expected = Int.toStringAs Int.binary i
    actual = toNumberAs Bin si
    si = fromInt b i

propBitSize :: ArbSignedInt32 -> Result
propBitSize (ArbSignedInt32 si) =
  expected == actual
    <?> "\nExpected:  " <> show expected
    <>  "\nActual:    " <> show actual
    <>  "\nSignedInt: " <> show si
  where
    expected = 32
    actual = Bin.length (Bin.toBits si)

propNegation :: ArbSignedInt32 -> Result
propNegation (ArbSignedInt32 si) =
  expected == actual
    <?> "\nExpected:  " <> show expected
    <>  "\nActual:    " <> show actual
    <>  "\nSignedInt: " <> show si
  where
    expected = si
    actual = foldr compose id (replicate 8 negate) $ si

propIntRoundtrip :: ArbInt -> Result
propIntRoundtrip (ArbInt i) = i === i' where
  i' = toInt si
  si = fromInt d32 i

propBinString :: ArbSignedInt32 -> Result
propBinString (ArbSignedInt32 ui) =
  let x = toStringAs Bin ui
  in all (\d -> d == '1' || d == '0') (Str.toCharArray x)
    <?> "String representation of SignedInt contains not only digits 1 and 0: " <> x

propBinStringEmptiness :: ArbSignedInt32 -> Result
propBinStringEmptiness (ArbSignedInt32 ui) =
  not Str.null (toStringAs Bin ui)
    <?> "String representation of SignedInt must not be empty"

propBinStringUniqness :: Array ArbSignedInt32 -> Result
propBinStringUniqness as = A.length sts === A.length uis where
  sts = A.nub $ map (toStringAs Bin) uis
  uis = A.nub $ map unwrap as

propAddition :: ArbInt -> ArbInt -> Result
propAddition (ArbInt a) (ArbInt b) =
  expected == actual
    <?> "\nExpected:          " <> show expected
    <>  "\nActual:            " <> show actual
    <>  "\nInt (left):        " <> show a
    <>  "\nInt (right):       " <> show b
    <>  "\nSignedInt (left):  " <> show (si a)
    <>  "\nSignedInt (right): " <> show (si b)
    <>  "\nSignedInt (sum):   " <> show sum
  where
    expected = a + b
    actual = toInt sum
    sum = si a + si b
    si = fromInt d32

propMultiplication :: ArbInt -> ArbInt -> Result
propMultiplication (ArbInt a) (ArbInt b) =
  expected == actual
    <?> "\nExpected:          " <> show expected
    <>  "\nActual:            " <> show actual
    <>  "\nInt (a):           " <> show a
    <>  "\nInt (b):           " <> show b
    <>  "\nSignedInt (a):     " <> show (si a)
    <>  "\nSignedInt (b):     " <> show (si b)
    <>  "\nSignedInt (mul):   " <> show res
  where
    actual = toInt res
    expected = a `imul` b
    res = si a * si b
    si = fromInt d32
