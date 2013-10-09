{-# LANGUAGE TemplateHaskell #-}

module Database.Relational.Schema.Oracle
    ( normalizeColumn, notNull, getType
    , columnsQuerySQL, primaryKeyQuerySQL
    ) where

import Control.Applicative ((<|>))
import Data.Char (toLower)
import Data.Int (Int32)
import Data.Map (Map)
import qualified Data.Map as Map

import Language.Haskell.TH (TypeQ)

import Database.Relational.Query

import Database.Relational.Schema.OracleSyscat.ConsColumns (dbaConsColumns)
import qualified Database.Relational.Schema.OracleSyscat.ConsColumns as ConsCols
import Database.Relational.Schema.OracleSyscat.Constraints (dbaConstraints)
import qualified Database.Relational.Schema.OracleSyscat.Constraints as Cons
import Database.Relational.Schema.OracleSyscat.TabColumns (DbaTabColumns, dbaTabColumns)
import qualified Database.Relational.Schema.OracleSyscat.TabColumns as Cols

-- NOT COMPLETED
-- (ref: http://docs.oracle.com/cd/B28359_01/server.111/b28318/datatype.htm)
-- | Mapping between type in Oracle DB and Haskell type.
mapFromSqlDefault :: Map String TypeQ
mapFromSqlDefault = Map.fromList
    [ ("CHAR", [t|Char|])
    -- , ("varchar", [t|String|])
    , ("VARCHAR2", [t|String|])
    , ("NCHAR", [t|Char|])
    -- , ("nvarchar", [t|String|])
    , ("NVARCHAR2", [t|String|])
    , ("NUMBER", [t|Int32|]) -- Double?
    , ("BINARY_FLOAT", [t|Float|])
    , ("BINARY_DOUBLE", [t|Double|])
    ]

-- | Normalize column name string to query Oracle DB system catalog.
normalizeColumn :: String -> String
normalizeColumn = map toLower

-- | Not-null attribute information of column.
notNull :: DbaTabColumns -> Bool
notNull = (== Just "N") . Cols.nullable

-- | Get column normalized name and column Haskell type.
getType :: Map String TypeQ -- ^ Type mapping specified by user
        -> DbaTabColumns -- ^ Column info in data dictionary
        -> Maybe (String, TypeQ) -- ^ Result normalized name and mapped Haskell type
getType mapFromSql cols = do
    key <- Cols.dataType cols
    typ <- Map.lookup key mapFromSql <|> Map.lookup key mapFromSqlDefault
    return (normalizeColumn $ Cols.columnName cols, mayNull typ)
  where
    mayNull typ
        | notNull cols = typ
        | otherwise = [t|Maybe $(typ)|]

-- | 'Relation' to query 'DbaTabColumns' from owner name and table name.
columnsRelationFromTable :: Relation (String, String) DbaTabColumns
columnsRelationFromTable = relation' $ do
    cols <- query dbaTabColumns
    (owner, ()) <- placeholder $ \owner ->
        wheres $ cols ! Cols.owner' .=. owner
    (name, ()) <- placeholder $ \name ->
        wheres $ cols ! Cols.tableName' .=. name
    asc $ cols ! Cols.columnId'
    return (owner >< name, cols)

-- | Phantom typed 'Query' to get 'DbaTabColumns' from owner name and table name.
columnsQuerySQL :: Query (String, String) DbaTabColumns
columnsQuerySQL = relationalQuery columnsRelationFromTable

-- | 'Relation' to query primary key name from owner name and table name.
primaryKeyRelation :: Relation (String, String) (Maybe String)
primaryKeyRelation = relation' $ do
    cons <- query dbaConstraints
    cols <- query dbaTabColumns
    consCols <- query dbaConsColumns

    wheres $ cons ! Cons.owner' .=. just (cols ! Cols.owner')
    wheres $ cons ! Cons.tableName' .=. cols ! Cols.tableName'
    wheres $ consCols ! ConsCols.columnName' .=. just (cols ! Cols.columnName')
    wheres $ cons ! Cons.constraintName' .=. consCols ! ConsCols.constraintName'

    wheres $ cols ! Cols.nullable' .=. just (value "N")
    wheres $ cons ! Cons.constraintType' .=. just (value "P")

    (owner, ()) <- placeholder $ \owner ->
        wheres $ cons ! Cons.owner' .=. just owner
    (name, ()) <- placeholder $ \name ->
        wheres $ cons ! Cons.tableName' .=. name

    asc $ consCols ! ConsCols.position'

    return (owner >< name, consCols ! ConsCols.columnName')

-- | Phantom typed 'Query' to get primary key name from owner name and table name.
primaryKeyQuerySQL :: Query (String, String) (Maybe String)
primaryKeyQuerySQL = relationalQuery primaryKeyRelation