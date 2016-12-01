{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveDataTypeable #-}

module Tester where

import           Data.Typeable
import           Data.Text(Text)
import qualified Data.Text as T
import qualified Data.Text.IO as T

import           System.IO 
import           System.Directory
import           Control.Exception


-- submission results
data Result = Result { resultClassify :: !Classify
                     , resultMessage :: !Text
                     }
              deriving (Eq, Read, Show, Typeable)

-- classification
data Classify = Received
              | Accepted
              | WrongAnswer
              | CompileError
              | RuntimeError
              | TimeLimitExceeded
              | MemoryLimitExceeded
              | MiscError
              deriving (Eq, Read, Show, Typeable)

instance Exception Result -- default instance


-- | auxiliary construtors
received = Result Received . trim maxLen
accepted = Result Accepted . trim maxLen
wrongAnswer = Result WrongAnswer . trim maxLen
compileError = Result CompileError . trim maxLen
runtimeError = Result RuntimeError . trim maxLen
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
withTextTemp :: FilePath -> Text -> (FilePath -> IO a) -> IO a
withTextTemp name contents cont
  = withTempFile name (\(f,h) -> T.hPutStr h contents >> hClose h >> cont f)

withTempFile :: FilePath -> ((FilePath, Handle) -> IO a) -> IO a
withTempFile name k = bracket create (\(f,_) -> removeFile f) k
  where create = do
          tmpDir <- getTemporaryDirectory
          openTempFileWithDefaultPermissions tmpDir name



  
