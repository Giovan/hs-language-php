module Evaluator where

import Tokenizer
import Conversion
import Data.IORef
import Data.Maybe
import Control.Monad.Error
import Control.Monad.Reader
import Control.Monad.Trans.Class

phpSum :: PHPValue -> PHPValue -> PHPValue
phpSum (PHPFloat a) (PHPFloat b) = PHPFloat (a + b)
phpSum (PHPInt a) (PHPInt b) = PHPInt (a + b)
phpSum a@(PHPFloat _) b = phpSum a (castToFloat b)
phpSum a b@(PHPFloat _) = phpSum (castToFloat a) b
phpSum a@(PHPInt _) b = phpSum a (castToInt b)
phpSum a b@(PHPInt _) = phpSum (castToInt a) b
phpSum a b = phpSum (castToInt a) (castToInt b)

data PHPError = UndefinedVariable String
              | NotEnoughArguments String
              | NotFound String String
              | Default String

showPHPError :: PHPError -> String
showPHPError (UndefinedVariable s) = "undefined variable: " ++ s
showPHPError (NotEnoughArguments s) = "Function '" ++ s ++ "' was not passed enough arguments"
showPHPError (NotFound msg name) = msg ++ ": " ++ name
showPHPError (Default s) = "error: " ++ s

instance Show PHPError where
    show = showPHPError

instance Error PHPError where
    noMsg = Default "Error"
    strMsg = Default

type PHPFunctionType = [PHPValue] -> PHPEval PHPValue

type VariableList = [(String, IORef PHPValue)]
type VariableEnv = IORef VariableList

type FunctionList = [(String, PHPFunctionType)]
type FunctionEnv = IORef FunctionList

data EvalConfig = EvalConfig { variableEnv :: VariableEnv
                             , functionEnv :: FunctionEnv
                             , globalRef :: Maybe VariableEnv
                             , varTypeChecks :: Bool
                             , disableIO :: Bool
                             }

type ErrMonad = ErrorT PHPError IO

type PHPEval = ReaderT EvalConfig ErrMonad

emptyEnv :: IO (IORef [a])
emptyEnv = newIORef []

defaultConfig :: IO EvalConfig
defaultConfig = do
    v <- emptyEnv
    f <- emptyEnv
    return $ EvalConfig v f Nothing False False

-- returns reference to local var environment
-- could be global, if variable is at root level execution
varEnvRef :: PHPEval VariableEnv
varEnvRef = liftM variableEnv ask

-- returns reference to global var env even if inside a function
globalVarsRef :: PHPEval VariableEnv
globalVarsRef = do
    mref <- liftM globalRef ask
    case mref of
      Nothing  -> varEnvRef
      Just ref -> return ref


globalFunctionsRef :: PHPEval FunctionEnv
globalFunctionsRef = liftM functionEnv ask

varDefs :: PHPEval VariableList
varDefs = varEnvRef >>= liftIO . readIORef

isDefined :: String -> PHPEval Bool
isDefined var = varDefs >>= return . isJust . lookup var

getVar :: String -> PHPEval PHPValue
getVar var = do
    e <- varDefs
    maybe (throwError $ UndefinedVariable var)
          (liftIO . readIORef)
          (lookup var e)

setVar :: String -> PHPValue -> PHPEval PHPValue
setVar var val = do
    ref <- varEnvRef
    e <- liftIO $ readIORef ref
    defined <- isDefined var
    if defined
      then liftIO $ do
          writeIORef (fromJust $ lookup var e) val
          return val
      else liftIO $ do
          valueRef <- newIORef val
          writeIORef ref ((var, valueRef) : e)
          return val

lookupFunction :: String -> PHPEval (Maybe PHPFunctionType)
lookupFunction name = do
    gref <- globalFunctionsRef
    globalFuncs <- liftIO $ readIORef gref
    return $ lookup name globalFuncs

defineFunction :: String -> [FunctionArgumentDef] -> PHPStmt -> PHPEval ()
defineFunction name args body = do
    gref <- globalFunctionsRef
    globalFuncs <- liftIO $ readIORef gref
    case lookup name globalFuncs of
      Just _  -> throwError $ Default ("Cannot redeclare function " ++ name)
      Nothing -> liftIO $ do
        writeIORef gref ((name, makeFunction name args body) : globalFuncs) 
        return ()

makeFunction :: String -> [FunctionArgumentDef] -> PHPStmt -> PHPFunctionType
makeFunction name argDefs body =
    let requiredArgsCount = length $ dropWhile (isJust . argDefault) $ reverse argDefs
        requiredArgsCheck args = when (length args < requiredArgsCount) (throwError $ Default $ "Not enough arguments to function " ++ name)
        applyArgs args = mapM (uncurry setVarOrDef) $ zip argDefs $ concat [map Just args, repeat mzero]
        setVarOrDef def val = case val of
                                Just v  -> setVar (argName def) v
                                Nothing -> setVar (argName def) (fromJust $ argDefault def)
    in (\args -> do
          requiredArgsCheck args
          applyArgs args
          liftM stmtVal $ evalStmt body
          )

testFun :: PHPFunctionType
testFun args = do
    if (length args) /= 1
      then throwError $ NotEnoughArguments "test"
      else do
          liftIO $ print (stringFromPHPValue $ head args) 
          return $ PHPNull

evalExpr :: PHPExpr -> PHPEval PHPExpr
evalExpr (BinaryExpr op a b) = case op of
                                 Add -> do
                                     av <- liftM exprVal (evalExpr a)
                                     bv <- liftM exprVal (evalExpr b)
                                     return $ Literal $ phpSum av bv
evalExpr a@(Literal _) = return a
evalExpr (Assign (PHPVariable varName) expr) = do
    v <- liftM exprVal (evalExpr expr)
    setVar varName v
    return $ Literal v

evalExpr (Assign (PHPVariableVariable vn) expr) = do
    var <- getVar vn
    evalExpr $ Assign (PHPVariable $ stringFromPHPValue var) expr

evalExpr (Variable (PHPVariable var)) = do
    val <- getVar var
    return $ Literal val

evalExpr (Variable (PHPVariableVariable vn)) = do
    var <- liftM stringFromPHPValue (getVar vn)
    evalExpr $ Variable (PHPVariable var)

evalExpr (Call (FunctionCall n) args) = do
        mfn <- lookupFunction n
        case mfn of
          Nothing -> throwError $ NotFound "Function not found" n
          Just fn -> do
              locals <- liftIO $ emptyEnv
              globalRef <- globalVarsRef
              args' <- mapM evalExpr args
              let vals = map exprVal args'
              local (localEnv locals globalRef) $ liftM Literal $ fn vals
    where
        localEnv locals globals env = env { variableEnv = locals, globalRef = Just globals }

exprVal :: PHPExpr -> PHPValue
exprVal (Literal v) = v
exprVal _ = error "Value that are not literals must be evaluated first"

stmtVal :: PHPStmt -> PHPValue
stmtVal (Expression e) = exprVal e
stmtVal _ = error "Only expressions can be evaluated into values"

stringFromPHPValue :: PHPValue -> String
stringFromPHPValue (PHPString s) = s
stringFromPHPValue _ = error "Non-PHPString values shouldn't be attempted to be converted to plain strings"

evalStmt :: PHPStmt -> PHPEval PHPStmt
evalStmt (Seq xs) = foldM (\_ x -> evalStmt x) (Seq []) xs
evalStmt (Expression expr) = liftM Expression (evalExpr expr)
evalStmt (Function name argDefs body) = defineFunction name argDefs body >> return (Seq [])

runPHPEval :: EvalConfig -> (PHPEval a) -> IO (Either PHPError a)
runPHPEval config eval = runErrorT $ runReaderT eval config
