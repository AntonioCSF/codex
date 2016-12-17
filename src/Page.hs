{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-
  Data types and methods for exercise pages
-}
module Page(
  Page(..),
  readPage,
  pageTitle,
  pageLanguage,
  pageCodeText,
  pageCode,
  pageIsExercise,
  pageValid,
  pageSplices
  ) where
 
import           Data.Maybe
import           Data.Text(Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as T

import           Data.Time 
import           Data.Map.Syntax
import           Heist.Splices     as I
import qualified Heist.Interpreted as I


import           Utils
import           Language.Types
import           Markdown
import           Interval
import           Text.Pandoc hiding (Code)
import           System.FilePath


-- | a document page; either a single exercise or an index
data Page  
  = Page { pagePath :: FilePath   -- ^ file path, relative to publicDir
         , pageMeta :: Meta       -- ^ meta data
         , pageDescription :: [Block]  -- ^ document blocks
         } deriving Show


-- | read a page from a markdown file
readPage :: FilePath -> FilePath -> IO Page
readPage base path = do
  Pandoc meta blocks <- readMarkdownFile (base </> path)
  return Page { pagePath = path
              , pageMeta = meta
              , pageDescription = blocks
              }

    
pageTitle :: Page -> Maybe [Inline]
pageTitle p
  = let t = docTitle (pageMeta p)
    in if null t then firstHeader (pageDescription p) else Just t

firstHeader :: [Block] -> Maybe [Inline]
firstHeader blocks = listToMaybe [h | Header _ _ h <- blocks]

{-
-- | fetch page tags
getTags :: Page -> [Text]
getTags Page{..}
  = fromMaybe [] (lookupFromMeta "tags" meta)
-}

pageLanguage :: Page -> Maybe Language
pageLanguage = lookupFromMeta "language" . pageMeta 

pageCodeText :: Page -> Maybe Text
pageCodeText = lookupFromMeta "code" . pageMeta

pageCode :: Page -> Maybe Code
pageCode p = Code <$> pageLanguage p <*> pageCodeText p


-- | is this an exercise page?
pageIsExercise :: Page -> Bool
pageIsExercise p
  = fromMaybe False $ lookupFromMeta "exercise" (pageMeta p)

-- | time interval for valid submissions
-- first argument is current time
pageValid :: ZonedTime -> Page -> Maybe Interval
pageValid t p
  = lookupFromMeta "valid" (pageMeta p) >>= readInterval t


-----------------------------------------------------------------------------

-- | splices related to a page
pageSplices :: Page -> ISplices
pageSplices page = do
  let dir = takeDirectory $ pagePath page
  "file-path" ## I.textSplice (T.pack $ pagePath page)      
  "file-path-url" ## I.textSplice (T.decodeUtf8 $ encodePath $ pagePath page)
  "page-description" ## return (blocksToHtml $ pageDescription page)
  "if-exercise" ## I.ifElseISplice (pageIsExercise page)
