{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveDataTypeable #-}

module Tester where

import           Data.Typeable
import           Data.Text(Text)
import qualified Data.Text as T
import qualified Data.Text.IO as T

import           System.FilePath
import           System.IO 
import           System.Directory
import           Control.Exception

-- import           Problem (Problem)

import           Types

-- submission results
data Result = Result { resultClassify :: !Classify
                     , resultMessage :: !Text
                     }
              deriving (Eq, Read, Show)

-- classification
data Classify = Accepted
              | WrongAnswer
              | CompileError
              | RuntimeError
              | TimeLimitExceeded
              | MemoryLimitExceeded
              | MiscError
              deriving (Eq, Read, Show, Typeable)


-- | auxiliary construtors
accepted = Result Accepted . trim maxLen
wrongAnswer = Result WrongAnswer . trim maxLen
compileError = Result CompileError . trim maxLen
runtimeError = Result CompileError . trim maxLen
timeLimitExceeded = Result TimeLimitExceeded . trim maxLen
memoryLimitExceeded = Result MemoryLimitExceeded . trim maxLen
miscError = Result MiscError . trim maxLen

maxLen = 2000

-- | trim a text to a maximum length
trim :: Int -> Text -> Text
trim maxlen txt
  | T.length txt <= maxlen = txt
  | otherwise = T.append (T.take maxlen txt) "\n**Output too long (truncated)***\n"

-- | match a piece of text  
match :: Text -> Text -> Bool
match = T.isInfixOf


-- | aquire and release temporary files
withTextTemp :: String -> Text -> (FilePath -> IO a) -> IO a
withTextTemp name txt cont = withTempFile name cont'
   where cont' (f,h) = T.hPutStr h txt >> hClose h >> cont f

withTempFile :: String -> ((FilePath,Handle) -> IO a) -> IO a
withTempFile name k = bracket createTemp (\(f,_)->removeFile f) k
  where createTemp = do
          tempDir <- getTemporaryDirectory
          openTempFileWithDefaultPermissions tempDir name


  