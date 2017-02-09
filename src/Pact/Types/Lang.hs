{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE DeriveFoldable #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE BangPatterns #-}

-- |
-- Module      :  Pact.Types
-- Copyright   :  (C) 2016 Stuart Popejoy
-- License     :  BSD-style (see the file LICENSE)
-- Maintainer  :  Stuart Popejoy <stuart@kadena.io>
--
-- Language types: 'Exp', 'Term', 'Type'.
--

module Pact.Types.Lang
 (
   Parsed(..),
   Code(..),
   Info(..),
   renderInfo,
   ModuleName(..),
   Name(..),
   Literal(..),
   simpleISO8601,formatLTime,
   TypeName(..),
   Arg(..),aInfo,aName,aType,
   FunType(..),ftArgs,ftReturn,
   FunTypes,funTypes,showFunTypes,
   PrimType(..),
   litToPrim,
   tyInteger,tyDecimal,tyTime,tyBool,tyString,
   tyList,tyObject,tyValue,tyKeySet,tyTable,
   SchemaType(..),
   TypeVarName(..),typeVarName,
   TypeVar(..),tvName,tvConstraint,
   Type(..),tyFunType,tyListType,tySchema,tySchemaType,tyUser,tyVar,
   mkTyVar,mkTyVar',mkSchemaVar,
   isAnyTy,isVarTy,isUnconstrainedTy,canUnifyWith,
   Exp(..),eLiteral,eAtom,eBinding,eList,eObject,eParsed,eQualifier,eSymbol,eType,
   _ELiteral,_ESymbol,_EAtom,_EList,_EObject,_EBinding,
   PublicKey(..),
   KeySet(..),
   KeySetName(..),
   DefType(..),
   defTypeRep,
   NativeDefName(..),
   FunApp(..),faDefType,faDocs,faInfo,faModule,faName,faTypes,
   Ref(..),
   NativeDFun(..),
   BindType(..),
   TableName(..),
   Module(..),
   Term(..),
   tAppArgs,tAppFun,tBindBody,tBindPairs,tBindType,tConstArg,tConstVal,
   tDefBody,tDefName,tDefType,tDocs,tFields,tFunTypes,tFunType,tInfo,tKeySet,
   tListType,tList,tLiteral,tModuleBody,tModuleDef,tModuleName,tModule,
   tNativeDocs,tNativeFun,tNativeName,tObjectType,tObject,tSchemaName,
   tStepEntity,tStepExec,tStepRollback,tTableName,tTableType,tValue,tVar,
   ToTerm(..),
   toTermList,
   typeof,
   pattern TLitString,pattern TLitInteger,tLit,tStr,termEq,abbrev
   ) where


import Control.Lens hiding (op,(.=))
import Text.Trifecta.Delta hiding (Columns)
import Control.Applicative
import Data.List
import Control.Monad
import Prelude hiding (exp)
import Control.Arrow hiding (app,(<+>))
import Prelude.Extras
import Bound
import Data.Text (Text,pack,unpack)
import qualified Data.Text as T
import Data.Text.Encoding
import Data.Aeson
import qualified Data.ByteString.UTF8 as BS
import qualified Data.ByteString.Lazy.UTF8 as BSL
import Data.String
import Data.Default
import Data.Char
import Data.Thyme
import Data.Thyme.Format.Aeson ()
import System.Locale
import Data.Scientific
import GHC.Generics
import Data.Decimal
import Data.Hashable
import Data.List.NonEmpty (NonEmpty (..))
import Data.Foldable
import qualified Text.PrettyPrint.ANSI.Leijen as PP
import Text.PrettyPrint.ANSI.Leijen hiding ((<>),(<$>))
import Data.Monoid


import Data.Serialize (Serialize)

import Pact.Types.Orphans ()
import Pact.Types.Util


-- | Code location, length from parsing.
data Parsed = Parsed {
  _pDelta :: Delta,
  _pLength :: Int
  } deriving (Eq,Show,Ord)
instance Default Parsed where def = Parsed mempty 0
instance HasBytes Parsed where bytes = bytes . _pDelta
instance Pretty Parsed where pretty = pretty . _pDelta


newtype Code = Code { _unCode :: Text }
  deriving (Eq,Ord,IsString,ToJSON,FromJSON,Monoid)
instance Show Code where show = unpack . _unCode
instance Pretty Code where
  pretty (Code c) | T.compareLength c maxLen == GT =
                      text $ unpack (T.take maxLen c <> "...")
                  | otherwise = text $ unpack c
    where maxLen = 30

-- | For parsed items, original code and parse info;
-- for runtime items, nothing
data Info = Info { _iInfo :: !(Maybe (Code,Parsed)) }

-- show instance uses Trifecta renderings
instance Show Info where
    show (Info Nothing) = ""
    show (Info (Just (r,_d))) = renderCompactString r
instance Eq Info where
    Info Nothing == Info Nothing = True
    Info (Just (_,d)) == Info (Just (_,e)) = d == e
    _ == _ = False
instance Ord Info where
  Info Nothing <= Info Nothing = True
  Info (Just (_,d)) <= Info (Just (_,e)) = d <= e
  Info Nothing <= _ = True
  _ <= Info Nothing = False


instance Default Info where def = Info Nothing


-- renderer for line number output.
renderInfo :: Info -> String
renderInfo (Info Nothing) = ""
renderInfo (Info (Just (_,Parsed d _))) =
    case d of
      (Directed f l c _ _) -> BS.toString f ++ ":" ++ show (succ l) ++ ":" ++ show c
      (Lines l c _ _) -> "<interactive>:" ++ show (succ l) ++ ":" ++ show c
      _ -> "<interactive>:0:0"


newtype ModuleName = ModuleName String
    deriving (Eq,Ord,IsString,ToJSON,FromJSON,AsString,Hashable,Pretty)
instance Show ModuleName where show (ModuleName s) = show s


data Name =
    QName { _nQual :: ModuleName, _nName :: String } |
    Name { _nName :: String }
         deriving (Eq,Ord,Generic)
instance Show Name where
    show (QName q n) = asString q ++ "." ++ n
    show (Name n) = n
instance ToJSON Name where toJSON = toJSON . show
instance Hashable Name


data Literal =
    LString { _lString :: !String } |
    LInteger { _lInteger :: !Integer } |
    LDecimal { _lDecimal :: !Decimal } |
    LBool { _lBool :: !Bool } |
    LTime { _lTime :: !UTCTime }
          deriving (Eq,Generic)
instance Serialize Literal


-- | ISO8601 Thyme format
simpleISO8601 :: String
simpleISO8601 = "%Y-%m-%dT%H:%M:%SZ"

formatLTime :: UTCTime -> String
formatLTime = formatTime defaultTimeLocale simpleISO8601
{-# INLINE formatLTime #-}


instance Show Literal where
    show (LString s) = show s
    show (LInteger i) = show i
    show (LDecimal r) = show r
    show (LBool b) = map toLower $ show b
    show (LTime t) = show $ formatLTime t
instance ToJSON Literal where
    toJSON (LString s) = String (pack s)
    toJSON (LInteger i) = Number (scientific i 0)
    toJSON (LDecimal r) = toJSON (show r)
    toJSON (LBool b) = toJSON b
    toJSON (LTime t) = toJSON (formatLTime t)
    {-# INLINE toJSON #-}


newtype TypeName = TypeName String
  deriving (Eq,Ord,IsString,AsString,ToJSON,FromJSON,Pretty)
instance Show TypeName where show (TypeName s) = show s

-- | Pair a name and a type (arguments, bindings etc)
data Arg o = Arg {
  _aName :: String,
  _aType :: Type o,
  _aInfo :: Info
  } deriving (Eq,Ord,Functor,Foldable,Traversable)
instance Show o => Show (Arg o) where show (Arg n t _) = n ++ ":" ++ show t
instance (Pretty o) => Pretty (Arg o)
  where pretty (Arg n t _) = pretty n PP.<> colon PP.<> pretty t

-- | Function type
data FunType o = FunType {
  _ftArgs :: [Arg o],
  _ftReturn :: Type o
  } deriving (Eq,Ord,Functor,Foldable,Traversable)
instance Show o => Show (FunType o) where
  show (FunType as t) = "(" ++ unwords (map show as) ++ ")->" ++ show t
instance (Pretty o) => Pretty (FunType o) where
  pretty (FunType as t) = parens (hsep (map pretty as)) PP.<> "->" PP.<> pretty t

-- | use NonEmpty for function types
type FunTypes o = NonEmpty (FunType o)

funTypes :: FunType o -> FunTypes o
funTypes ft = ft :| []
showFunTypes :: Show o => FunTypes o -> String
showFunTypes (t :| []) = show t
showFunTypes ts = show (toList ts)

data PrimType =
  TyInteger |
  TyDecimal |
  TyTime |
  TyBool |
  TyString |
  TyValue |
  TyKeySet
  deriving (Eq,Ord)

litToPrim :: Literal -> PrimType
litToPrim LString {} = TyString
litToPrim LInteger {} = TyInteger
litToPrim LDecimal {} = TyDecimal
litToPrim LBool {} = TyBool
litToPrim LTime {} = TyTime

tyInteger,tyDecimal,tyTime,tyBool,tyString,tyList,tyObject,tyValue,tyKeySet,tyTable :: String
tyInteger = "integer"
tyDecimal = "decimal"
tyTime = "time"
tyBool = "bool"
tyString = "string"
tyList = "list"
tyObject = "object"
tyValue = "value"
tyKeySet = "keyset"
tyTable = "table"

instance Show PrimType where
  show TyInteger = tyInteger
  show TyDecimal = tyDecimal
  show TyTime = tyTime
  show TyBool = tyBool
  show TyString = tyString
  show TyValue = tyValue
  show TyKeySet = tyKeySet
instance Pretty PrimType where pretty = text . show

data SchemaType =
  TyTable |
  TyObject |
  TyBinding
  deriving (Eq,Ord)
instance Show SchemaType where
  show TyTable = tyTable
  show TyObject = tyObject
  show TyBinding = "binding"
instance Pretty SchemaType where pretty = text . show

newtype TypeVarName = TypeVarName { _typeVarName :: String }
  deriving (Eq,Ord,IsString,AsString,ToJSON,FromJSON,Hashable,Pretty)
instance Show TypeVarName where show = _typeVarName

-- | Type variables are namespaced for value types and schema types.
data TypeVar v =
  TypeVar { _tvName :: TypeVarName, _tvConstraint :: [Type v] } |
  SchemaVar { _tvName :: TypeVarName }
  deriving (Functor,Foldable,Traversable)
instance Eq (TypeVar v) where
  (TypeVar a _) == (TypeVar b _) = a == b
  (SchemaVar a) == (SchemaVar b) = a == b
  _ == _ = False
instance Ord (TypeVar v) where
  x `compare` y = case (x,y) of
    (TypeVar {},SchemaVar {}) -> LT
    (SchemaVar {},TypeVar {}) -> GT
    (TypeVar a _,TypeVar b _) -> a `compare` b
    (SchemaVar a,SchemaVar b) -> a `compare` b
instance Show v => Show (TypeVar v) where
  show (TypeVar n []) = "<" ++ show n ++ ">"
  show (TypeVar n cs) = "<" ++ show n ++ show cs ++ ">"
  show (SchemaVar n) = "<{" ++ show n ++ "}>"
instance (Pretty v) => Pretty (TypeVar v) where
  pretty (TypeVar n []) = angles (pretty n)
  pretty (TypeVar n cs) = angles (pretty n <+> brackets (hsep (map pretty cs)))
  pretty (SchemaVar n) = angles (braces (pretty n))


-- | Pact types.
data Type v =
  TyAny |
  TyVar { _tyVar :: TypeVar v } |
  TyPrim PrimType |
  TyList { _tyListType :: Type v } |
  TySchema { _tySchema :: SchemaType, _tySchemaType :: Type v } |
  TyFun { _tyFunType :: FunType v } |
  TyUser { _tyUser :: v }
    deriving (Eq,Ord,Functor,Foldable,Traversable)

instance (Show v) => Show (Type v) where
  show (TyPrim t) = show t
  show (TyList t) | isAnyTy t = tyList
                  | otherwise = "[" ++ show t ++ "]"
  show (TySchema s t) | isAnyTy t = show s
                      | otherwise = show s ++ ":" ++ show t
  show (TyFun f) = show f
  show (TyUser v) = show v
  show TyAny = "*"
  show (TyVar n) = show n

instance (Pretty o) => Pretty (Type o) where
  pretty ty = case ty of
    TyVar n -> pretty n
    TyUser v -> pretty v
    TyFun f -> pretty f
    TySchema s t -> pretty s PP.<> colon PP.<> pretty t
    TyList t -> "list:" PP.<> pretty t
    TyPrim t -> pretty t
    TyAny -> "*"

mkTyVar :: String -> [Type n] -> Type n
mkTyVar n cs = TyVar (TypeVar (fromString n) cs)
mkTyVar' :: String -> Type n
mkTyVar' n = mkTyVar n []
mkSchemaVar :: String -> Type n
mkSchemaVar n = TyVar (SchemaVar (fromString n))

isAnyTy :: Type v -> Bool
isAnyTy TyAny = True
isAnyTy _ = False

isVarTy :: Type v -> Bool
isVarTy TyVar {} = True
isVarTy _ = False

isUnconstrainedTy :: Type v -> Bool
isUnconstrainedTy TyAny = True
isUnconstrainedTy (TyVar (TypeVar _ [])) = True
isUnconstrainedTy _ = False

-- | a `canUnifyWith` b means a "can represent/contains" b
canUnifyWith :: Eq n => Type n -> Type n -> Bool
canUnifyWith TyAny _ = True
canUnifyWith _ TyAny = True
canUnifyWith (TyVar (SchemaVar _)) TyUser {} = True
canUnifyWith (TyVar SchemaVar {}) (TyVar SchemaVar {}) = True
canUnifyWith (TyVar (TypeVar _ ac)) (TyVar (TypeVar _ bc)) = all (`elem` ac) bc
canUnifyWith (TyVar (TypeVar _ cs)) b = null cs || b `elem` cs
canUnifyWith (TyList a) (TyList b) = a `canUnifyWith` b
canUnifyWith (TySchema _ a) (TySchema _ b) = a `canUnifyWith` b
canUnifyWith a b = a == b

makeLenses ''Type
makeLenses ''FunType
makeLenses ''Arg
makeLenses ''TypeVar
makeLenses ''TypeVarName



data Exp =
  ELiteral { _eLiteral :: !Literal, _eParsed :: !Parsed } |
  ESymbol { _eSymbol :: !String, _eParsed :: !Parsed } |
  EAtom { _eAtom :: !String
        , _eQualifier :: !(Maybe String)
        , _eType :: !(Maybe (Type TypeName))
        , _eParsed :: !Parsed
        } |
  EList { _eList :: ![Exp], _eParsed :: !Parsed } |
  EObject { _eObject :: ![(Exp,Exp)], _eParsed :: !Parsed } |
  EBinding { _eBinding :: ![(Exp,Exp)], _eParsed :: !Parsed }
           deriving (Eq,Generic)
makePrisms ''Exp


maybeDelim :: Show a => String -> Maybe a -> String
maybeDelim d t = maybe "" ((d ++) . show) t


instance Show Exp where
    show (ELiteral i _) = show i
    show (ESymbol s _) = '\'':s
    show (EAtom a q t _) =  a ++ maybeDelim "."  q ++ maybeDelim ": " t
    show (EList ls _) = "(" ++ unwords (map show ls) ++ ")"
    show (EObject ps _) = "{ " ++ intercalate ", " (map (\(k,v) -> show k ++ ": " ++ show v) ps) ++ " }"
    show (EBinding ps _) = "{ " ++ intercalate ", " (map (\(k,v) -> show k ++ ":= " ++ show v) ps) ++ " }"

$(makeLenses ''Exp)




data PublicKey = PublicKey { _pubKey :: !BS.ByteString } deriving (Eq,Ord,Generic)

instance Serialize PublicKey
instance FromJSON PublicKey where
    parseJSON = withText "PublicKey" (return . PublicKey . encodeUtf8)
instance ToJSON PublicKey where
    toJSON = toJSON . decodeUtf8 . _pubKey
instance Show PublicKey where show (PublicKey s) = show (BS.toString s)

-- | KeySet pairs keys with a predicate function name.
data KeySet = KeySet {
      _pksKeys :: ![PublicKey]
    , _pksPredFun :: !String
    } deriving (Eq,Generic)
instance Serialize KeySet
instance Show KeySet where show (KeySet ks f) = "KeySet " ++ show ks ++ " " ++ show f
instance FromJSON KeySet where
    parseJSON = withObject "KeySet" $ \o ->
                KeySet <$> o .: "keys" <*> o .: "pred"
instance ToJSON KeySet where
    toJSON (KeySet k f) = object ["keys" .= k, "pred" .= f]


newtype KeySetName = KeySetName String
    deriving (Eq,Ord,IsString,AsString,ToJSON,FromJSON)
instance Show KeySetName where show (KeySetName s) = show s


data DefType = Defun | Defpact deriving (Eq,Show)
defTypeRep :: DefType -> String
defTypeRep Defun = "defun"
defTypeRep Defpact = "defpact"

newtype NativeDefName = NativeDefName String
    deriving (Eq,Ord,IsString,ToJSON,AsString)
instance Show NativeDefName where show (NativeDefName s) = show s

-- | Capture function application metadata
data FunApp = FunApp {
      _faInfo :: !Info
    , _faName :: !String
    , _faModule :: !(Maybe ModuleName)
    , _faDefType :: !DefType
    , _faTypes :: !(FunTypes (Term Name))
    , _faDocs :: !(Maybe String)
    }

instance Show FunApp where
  show FunApp {..} =
    "(" ++ defTypeRep _faDefType ++ " " ++ maybeDelim "." _faModule ++
    _faName ++ " " ++ showFunTypes _faTypes ++ ")"



-- | Variable type for an evaluable 'Term'.
data Ref =
  -- | "Reduced" (evaluated) or native (irreducible) term.
  Direct (Term Name) |
  -- | Unevaulated/un-reduced term, never a native.
  Ref (Term Ref)
               deriving (Eq)
instance Show Ref where
    show (Direct t) = abbrev t
    show (Ref t) = abbrev t

data NativeDFun = NativeDFun {
      _nativeName :: NativeDefName,
      _nativeFun :: forall m . Monad m => FunApp -> [Term Ref] -> m (Term Name)
    }
instance Eq NativeDFun where a == b = _nativeName a == _nativeName b
instance Show NativeDFun where show a = show $ _nativeName a

-- | Binding forms.
data BindType n =
  -- | Normal "let" bind
  BindLet |
  -- | Schema-style binding, with string value for key
  BindSchema { _bType :: n }
  deriving (Eq,Functor,Foldable,Traversable,Ord)
instance (Show n) => Show (BindType n) where
  show BindLet = "let"
  show (BindSchema b) = "bind" ++ show b
instance (Pretty n) => Pretty (BindType n) where
  pretty BindLet = "let"
  pretty (BindSchema b) = "bind" PP.<> pretty b


newtype TableName = TableName String
    deriving (Eq,Ord,IsString,ToTerm,AsString,Hashable)
instance Show TableName where show (TableName s) = show s

data Module = Module {
    _mName :: !ModuleName
  , _mKeySet :: !KeySetName
  , _mDocs :: !(Maybe String)
  , _mCode :: !Code
  } deriving (Eq)
instance Show Module where
  show Module {..} =
    "(Module " ++ asString _mName ++ " '" ++ asString _mKeySet ++ maybeDelim " " _mDocs ++ ")"
instance ToJSON Module where
  toJSON Module {..} = object $
    ["name" .= _mName, "keyset" .= _mKeySet, "code" .= _mCode ]
    ++ maybe [] (return . ("docs" .=)) _mDocs
instance FromJSON Module where
  parseJSON = withObject "Module" $ \o -> Module <$>
    o .: "name" <*> o .: "keyset" <*> o .:? "docs" <*> o .: "code"

-- | Pact evaluable term.
data Term n =
    TModule {
      _tModuleDef :: Module
    , _tModuleBody :: !(Scope () Term n)
    , _tInfo :: !Info
    } |
    TList {
      _tList :: ![Term n]
    , _tListType :: Type (Term n)
    , _tInfo :: !Info
    } |
    TDef {
      _tDefName :: !String
    , _tModule :: !ModuleName
    , _tDefType :: !DefType
    , _tFunType :: !(FunType (Term n))
    , _tDefBody :: !(Scope Int Term n)
    , _tDocs :: !(Maybe String)
    , _tInfo :: !Info
    } |
    TNative {
      _tNativeName :: !NativeDefName
    , _tNativeFun :: !NativeDFun
    , _tFunTypes :: FunTypes (Term n)
    , _tNativeDocs :: String
    , _tInfo :: !Info
    } |
    TConst {
      _tConstArg :: !(Arg (Term n))
    , _tModule :: !ModuleName
    , _tConstVal :: !(Term n)
    , _tDocs :: !(Maybe String)
    , _tInfo :: !Info
    } |
    TApp {
      _tAppFun :: !(Term n)
    , _tAppArgs :: ![Term n]
    , _tInfo :: !Info
    } |
    TVar {
      _tVar :: !n
    , _tInfo :: !Info
    } |
    TBinding {
      _tBindPairs :: ![(Arg (Term n),Term n)]
    , _tBindBody :: !(Scope Int Term n)
    , _tBindType :: BindType (Type (Term n))
    , _tInfo :: !Info
    } |
    TObject {
      _tObject :: ![(Term n,Term n)]
    , _tObjectType :: !(Type (Term n))
    , _tInfo :: !Info
    } |
    TSchema {
      _tSchemaName :: !TypeName
    , _tModule :: !ModuleName
    , _tDocs :: !(Maybe String)
    , _tFields :: ![Arg (Term n)]
    , _tInfo :: !Info
    } |
    TLiteral {
      _tLiteral :: !Literal
    , _tInfo :: !Info
    } |
    TKeySet {
      _tKeySet :: !KeySet
    , _tInfo :: !Info
    } |
    TUse {
      _tModuleName :: !ModuleName
    , _tInfo :: !Info
    } |
    TValue {
      _tValue :: !Value
    , _tInfo :: !Info
    } |
    TStep {
      _tStepEntity :: !(Term n)
    , _tStepExec :: !(Term n)
    , _tStepRollback :: !(Maybe (Term n))
    , _tInfo :: !Info
    } |
    TTable {
      _tTableName :: !TableName
    , _tModule :: ModuleName
    , _tTableType :: !(Type (Term n))
    , _tDocs :: !(Maybe String)
    , _tInfo :: !Info
    }
    deriving (Functor,Foldable,Traversable,Eq)

instance Show n => Show (Term n) where
    show TModule {..} =
      "(TModule " ++ show _tModuleDef ++ " " ++ show _tModuleBody ++ ")"
    show (TList bs t _) = "[" ++ unwords (map show bs) ++ "]:" ++ show t
    show TDef {..} =
      "(TDef " ++ defTypeRep _tDefType ++ " " ++ asString _tModule ++ "." ++ _tDefName ++ " " ++
      show _tFunType ++ maybeDelim " " _tDocs ++ ")"
    show TNative {..} =
      "(TNative " ++ asString _tNativeName ++ " " ++ showFunTypes _tFunTypes ++ " " ++ _tNativeDocs ++ ")"
    show TConst {..} =
      "(TConst " ++ asString _tModule ++ "." ++ show _tConstArg ++ maybeDelim " " _tDocs ++ ")"
    show (TApp f as _) = "(TApp " ++ show f ++ " " ++ show as ++ ")"
    show (TVar n _) = "(TVar " ++ show n ++ ")"
    show (TBinding bs b c _) = "(TBinding " ++ show bs ++ " " ++ show b ++ " " ++ show c ++ ")"
    show (TObject bs ot _) =
      "{" ++ intercalate ", " (map (\(a,b) -> show a ++ ": " ++ show b) bs) ++ "}:" ++ show ot
    show (TLiteral l _) = show l
    show (TKeySet k _) = show k
    show (TUse m _) = "(TUse " ++ show m ++ ")"
    show (TValue v _) = BSL.toString $ encode v
    show (TStep ent e r _) =
      "(TStep " ++ show ent ++ " " ++ show e ++ maybeDelim " " r ++ ")"
    show TSchema {..} =
      "(TSchema " ++ asString _tModule ++ "." ++ asString _tSchemaName ++ " " ++
      show _tFields ++ maybeDelim " " _tDocs ++ ")"
    show TTable {..} =
      "(TTable " ++ asString _tModule ++ "." ++ asString _tTableName ++ ":" ++ show _tTableType
      ++ maybeDelim " " _tDocs ++ ")"


instance Show1 Term
instance Eq1 Term

instance Applicative Term where
    pure = return
    (<*>) = ap

instance Monad Term where
    return a = TVar a def
    TModule m b i >>= f = TModule m (b >>>= f) i
    TList bs t i >>= f = TList (map (>>= f) bs) (fmap (>>= f) t) i
    TDef n m dt ft b d i >>= f = TDef n m dt (fmap (>>= f) ft) (b >>>= f) d i
    TNative n fn t d i >>= f = TNative n fn (fmap (fmap (>>= f)) t) d i
    TConst d m c t i >>= f = TConst (fmap (>>= f) d) m (c >>= f) t i
    TApp af as i >>= f = TApp (af >>= f) (map (>>= f) as) i
    TVar n i >>= f = (f n) { _tInfo = i }
    TBinding bs b c i >>= f = TBinding (map (fmap (>>= f) *** (>>= f)) bs) (b >>>= f) (fmap (fmap (>>= f)) c) i
    TObject bs t i >>= f = TObject (map ((>>= f) *** (>>= f)) bs) (fmap (>>= f) t) i
    TLiteral l i >>= _ = TLiteral l i
    TKeySet k i >>= _ = TKeySet k i
    TUse m i >>= _ = TUse m i
    TValue v i >>= _ = TValue v i
    TStep ent e r i >>= f = TStep (ent >>= f) (e >>= f) (fmap (>>= f) r) i
    TSchema {..} >>= f = TSchema _tSchemaName _tModule _tDocs (fmap (fmap (>>= f)) _tFields) _tInfo
    TTable {..} >>= f = TTable _tTableName _tModule (fmap (>>= f) _tTableType) _tDocs _tInfo


instance FromJSON (Term n) where
    parseJSON (Number n) = return $ TLiteral (LInteger (round n)) def
    parseJSON (Bool b) = return $ toTerm b
    parseJSON (String s) = return $ toTerm (unpack s)
    parseJSON v = return $ toTerm v
    {-# INLINE parseJSON #-}

instance Show n => ToJSON (Term n) where
    toJSON (TLiteral l _) = toJSON l
    toJSON (TValue v _) = v
    toJSON (TKeySet k _) = toJSON k
    toJSON (TObject kvs _ _) =
        object $ map (kToJSON *** toJSON) kvs
            where kToJSON (TLitString s) = pack s
                  kToJSON t = pack (abbrev t)
    toJSON (TList ts _ _) = toJSON ts
    toJSON t = toJSON (abbrev t)
    {-# INLINE toJSON #-}

class ToTerm a where
    toTerm :: a -> Term m
instance ToTerm Bool where toTerm = tLit . LBool
instance ToTerm Integer where toTerm = tLit . LInteger
instance ToTerm Int where toTerm = tLit . LInteger . fromIntegral
instance ToTerm Decimal where toTerm = tLit . LDecimal
instance ToTerm String where toTerm = tLit . LString
instance ToTerm KeySet where toTerm = (`TKeySet` def)
instance ToTerm Literal where toTerm = tLit
instance ToTerm Value where toTerm = (`TValue` def)
instance ToTerm UTCTime where toTerm = tLit . LTime

toTermList :: (ToTerm a,Foldable f) => Type (Term b) -> f a -> Term b
toTermList ty l = TList (map toTerm (toList l)) ty def




typeof :: Term a -> Either String (Type (Term a))
typeof t = case t of
      TLiteral l _ -> Right $ TyPrim $ litToPrim l
      TModule {} -> Left "module"
      TList {..} -> Right $ TyList _tListType
      TDef {..} -> Left $ defTypeRep _tDefType
      TNative {..} -> Left "defun"
      TConst {..} -> Left $ "const:" ++ _aName _tConstArg
      TApp {..} -> Left "app"
      TVar {..} -> Left "var"
      TBinding {..} -> case _tBindType of
        BindLet -> Left "let"
        BindSchema bt -> Right $ TySchema TyBinding bt
      TObject {..} -> Right $ TySchema TyObject _tObjectType
      TKeySet {} -> Right $ TyPrim TyKeySet
      TUse {} -> Left "use"
      TValue {} -> Right $ TyPrim TyValue
      TStep {} -> Left "step"
      TSchema {..} -> Left $ "defobject:" ++ asString _tSchemaName
      TTable {..} -> Right $ TySchema TyTable _tTableType



pattern TLitString s <- TLiteral (LString s) _
pattern TLitInteger i <- TLiteral (LInteger i) _

tLit :: Literal -> Term n
tLit = (`TLiteral` def)
{-# INLINE tLit #-}

-- | Convenience for OverloadedStrings annoyances
tStr :: String -> Term n
tStr = toTerm

-- | Support pact `=` for value-level terms
termEq :: Eq n => Term n -> Term n -> Bool
termEq (TList a _ _) (TList b _ _) = length a == length b && and (zipWith termEq a b)
termEq (TObject a _ _) (TObject b _ _) = length a == length b && all (lkpEq b) a
    where lkpEq [] _ = False
          lkpEq ((k',v'):ts) p@(k,v) | termEq k k' && termEq v v' = True
                                     | otherwise = lkpEq ts p
termEq (TLiteral a _) (TLiteral b _) = a == b
termEq (TKeySet a _) (TKeySet b _) = a == b
termEq (TValue a _) (TValue b _) = a == b
termEq (TTable a b c d _) (TTable e f g h _) = a == e && b == f && c == g && d == h
termEq (TSchema a b c d _) (TSchema e f g h _) = a == e && b == f && c == g && d == h
termEq _ _ = False




abbrev :: Show t => Term t -> String
abbrev (TModule m _ _) = "<module " ++ asString (_mName m) ++ ">"
abbrev (TList bs _ _) = concatMap abbrev bs
abbrev TDef {..} = "<defun " ++ _tDefName ++ ">"
abbrev TNative {..} = "<native " ++ asString _tNativeName ++ ">"
abbrev TConst {..} = "<defconst " ++ show _tConstArg ++ ">"
abbrev t@TApp {} = "<app " ++ abbrev (_tAppFun t) ++ ">"
abbrev TBinding {} = "<binding>"
abbrev TObject {} = "<object>"
abbrev (TLiteral l _) = show l
abbrev TKeySet {} = "<keyset>"
abbrev (TUse m _) = "<use '" ++ show m ++ ">"
abbrev (TVar s _) = show s
abbrev (TValue v _) = show v
abbrev TStep {} = "<step>"
abbrev TSchema {..} = "<defschema " ++ asString _tSchemaName ++ ">"
abbrev TTable {..} = "<deftable " ++ asString _tTableName ++ ">"




makeLenses ''Term
makeLenses ''FunApp