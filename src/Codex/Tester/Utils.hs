
module Codex.Tester.Utils where

import           Data.Text(Text)
import qualified Data.Text as T
import qualified Data.Text.IO as T

import           Control.Exception
import           Control.Monad(when)
import           System.IO
import           System.Directory
import           System.Posix.Files 
import           Data.Bits

-- | match a piece of text
match :: Text -> Text -> Bool
match = T.isInfixOf


-- | aquire and release temporary files
withTextTemp :: FilePath -> Text -> (FilePath -> IO a) -> IO a
withTextTemp name contents cont
  = withTempFile name (\(f,h) -> T.hPutStr h contents >> hClose h >> cont f)



withTempFile :: FilePath -> ((FilePath, Handle) -> IO a) -> IO a
withTempFile name = bracket create (\(f,_) -> removeFile f)
  where create = do
          tmpDir <- getTemporaryDirectory
          openTempFileWithDefaultPermissions tmpDir name


-- | remove files if they exist, silently ignore otherwise
removeFileIfExists :: FilePath -> IO ()
removeFileIfExists f = do b<-doesFileExist f; when b (removeFile f)

cleanupFiles :: [FilePath] -> IO ()
cleanupFiles = mapM_ removeFileIfExists

-- | allow any user read access
allowAnyRead :: FilePath -> IO ()
allowAnyRead f = do
  mode <- fileMode <$> getFileStatus f
  setFileMode f (mode .|. ownerReadMode .|. otherReadMode .|. groupReadMode)
  
