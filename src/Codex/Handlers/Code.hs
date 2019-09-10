{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

--
-- Code exercise handlers
--
module Codex.Handlers.Code
  ( codeHandlers
  ) where

import          Codex.Types
import          Codex.Application
import          Codex.Utils
import          Codex.Handlers
import          Codex.Page
import          Codex.Policy
import          Codex.Submission
import          Codex.AceEditor
import          Codex.Evaluate

import           Snap.Snaplet.Heist
import           Snap.Snaplet.Router

import qualified Heist.Interpreted                           as I
import           Heist.Splices                               as I

import qualified Text.Pandoc.Builder as P

import           Data.Maybe (isJust)
import           Data.Map.Syntax
import qualified Data.Text                                   as T
import           Data.Time.LocalTime

import           Control.Monad (guard)
import           Control.Monad.IO.Class (liftIO)

-- is it an exercise page 
isExercise :: Page -> Bool
isExercise = isJust . pageTester

-- | get a coding exercise 
codeView :: UserLogin -> FilePath -> Page -> Codex ()
codeView uid rqpath page = do
  guard (isExercise page)
  tz <- liftIO getCurrentTimeZone
  subs <- getPageSubmissions uid rqpath
  withTimeSplices page $ renderWithSplices "_exercise" $ do
    pageSplices page
    codeSplices page
    feedbackSplices page
    submissionListSplices (pageValid page) tz subs
    textEditorSplice
    languageSplices (pageLanguages page) Nothing


codeSubmit :: UserLogin -> FilePath -> Page -> Codex ()
codeSubmit uid rqpath page = do
  guard (isExercise page)
  text <- require (getTextParam "code")
  lang <- Language <$> require (getTextParam "language")
  guard (lang `elem` pageLanguages page) 
  sid <- newSubmission uid rqpath (Code lang text)
  redirectURL (Report sid)

-- | report a code submission
codeReport :: FilePath -> Page -> Submission -> Codex ()
codeReport rqpath page sub = do
  guard (isExercise page)
  tz <- liftIO getCurrentTimeZone   
  withTimeSplices page $ renderWithSplices "_report" $ do
    urlSplices rqpath
    pageSplices page
    codeSplices page
    feedbackSplices page
    submitSplices tz sub
    textEditorSplice
    languageSplices (pageLanguages page) (Just $ submitLang sub)


-- | splices related to code exercises
codeSplices :: Page -> ISplices
codeSplices page = do
  "page-languages" ##
    I.textSplice $ T.intercalate "," $ map fromLanguage $ pageLanguages page
  "language-extensions" ##
   I.textSplice $ languageExtensions $ pageLanguages page
  "default-text" ## maybe (return []) I.textSplice (pageDefaultText page)


-- | splices relating to a list of submissions
submissionListSplices :: Policy t -> TimeZone -> [Submission] -> ISplices
submissionListSplices policy tz list = do
  -- number of submissions made
  let count = length list
  -- optional submissions left
  let left = fmap (\n -> max 0 (n - count)) (maxAttempts policy)
  "submissions-count" ## I.textSplice (T.pack $ show count)
  "if-submitted" ## I.ifElseISplice (count > 0)
  "submissions-list" ##
    I.mapSplices (I.runChildrenWith . submitSplices tz) list   
  "submissions-left" ##
    I.textSplice (maybe "N/A" (T.pack.show) left)




codePrintout :: Page -> Submission -> Codex P.Blocks
codePrintout page Submission{..} = do
  guard (isExercise page)
  let lang = T.unpack $ fromLanguage $ codeLang submitCode
  let code = T.unpack $ codeText submitCode
  return $ P.codeBlockWith ("", [lang, "numberLines"], []) code




codeHandlers :: Handlers Codex
codeHandlers
  = Handlers
    { handleView = codeView
    , handleSubmit = codeSubmit
    , handleReport = const codeReport
    , handlePrintout = const codePrintout
    }
