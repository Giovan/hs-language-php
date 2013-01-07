module Main where

import Test.Framework (defaultMain, testGroup, Test)
import Test.Framework.Providers.HUnit
import Test.HUnit hiding (Test)

import Tokenizer

import Control.Monad

main :: IO ()
main = defaultMain [testSuite]

testSuite :: Test
testSuite = testGroup "Parser"
            [ testCase "Assign int" (testFile "tests/assign_int.php" (show $ Seq [Expression (Assign (PHPVariable "foo") (Literal (PHPInt 1))) ]))
            , testCase "Assign bool" (testFile "tests/assign_bool.php" (
                    show $ Seq [ Expression (Assign (PHPVariable "foo") (Literal (PHPBool True)))
                               , Expression (Assign (PHPVariable "foo") (Literal (PHPBool False)))
                               ]))
            , testCase "Assign string double quote" (testFile "tests/assign_str_double_quote.php" (
                    show $ Seq [Expression (Assign (PHPVariable "foo") (Literal (PHPString "bar")))]))
            , testCase "Assign string single quote" (testFile "tests/assign_str_single_quote.php" (
                    show $ Seq [Expression (Assign (PHPVariable "foo") (Literal (PHPString "bar")))]))
            , testCase "Assign null" (testFile "tests/assign_null.php" (show $ Seq [Expression (Assign (PHPVariable "foo") (Literal PHPNull))]))
            , testCase "Assign float" (testFile "tests/assign_float.php" (show $ Seq [Expression (Assign (PHPVariable "foo") (Literal (PHPFloat 10.5)))]))
            , testCase "Assign var" (testFile "tests/assign_var.php" (show $ Seq [Expression (Assign (PHPVariable "foo") (Variable (PHPVariable "bar")))]))
            , testCase "If, plain" (testFile "tests/if_plain.php" (show $ Seq [If (Literal (PHPBool True)) (Seq []) Nothing]))
            , testCase "If, else" (testFile "tests/if_else.php" (show $ Seq [If (Literal (PHPBool True)) (Seq []) (Just (Else (Seq [])))]))
            , testCase "If, elseif, else" (testFile "tests/if_elseif_else.php" (
                    show $ Seq [If (Literal (PHPBool True)) (Seq []) 
                                  (Just (ElseIf (Literal (PHPBool True)) (Seq []) 
                                    (Just (Else (Seq [])))))]))
            , testCase "Math: simple add" (testFile "tests/math_simple_add.php" (
                    show $ Seq [Expression (BinaryExpr Add (Literal (PHPInt 1)) (Literal (PHPInt 1)))]))
            , testCase "Call: one arg" (testFile "tests/call_1_arg.php" (
                    show $ Seq [Expression (Call (FunctionCall "test") [Literal (PHPInt 1)])]))
            , testCase "Call: two args with whitespace" (testFile "tests/call_two_with_white.php" (
                    show $ Seq [Expression (Call (FunctionCall "test") [Literal (PHPBool True),Literal (PHPInt 1)])]))
            , testCase "Function: No args, no body" (testFile "tests/func_no_args_no_body.php" (
                    show $ Seq [Function "foo" [] (Seq [])]))
            , testCase "Function: Some args, no body" (testFile "tests/func_some_args_no_body.php" (
                    show $ Seq [Function "foo" [ FunctionArgumentDef {argName = "test", argDefault = Nothing}
                                               , FunctionArgumentDef {argName = "test2", argDefault = Nothing}] (Seq [])]))
            , testCase "Function: No args, simple body" (testFile "tests/func_no_args_simple_body.php" (
                    show $ Seq [Function "foo" [] (Seq [Expression (Assign (PHPVariable "hello") (Literal (PHPInt 1)))])]))
            , testCase "Function: Args with defaults" (testFile "tests/func_args_with_defaults.php" (
                    show $ Seq [Function "x" [ FunctionArgumentDef {argName = "a", argDefault = Just (PHPInt 1)}
                                             , FunctionArgumentDef {argName = "b", argDefault = Nothing}] (Seq [])]))
            ]

testFile :: FilePath -> String -> IO ()
testFile file expected = do
    res <- readFile file
    (expected @=? (show $ parseString res))
