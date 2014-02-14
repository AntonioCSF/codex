{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}

------------------------------------------------------------------------------
-- | This module is where all the routes and handlers are defined for your
-- site. The 'app' function is the initializer that combines everything
-- together and is exported by this module.
module Site
  ( app
  ) where

------------------------------------------------------------------------------
import           Prelude hiding (catch)
import           Control.Monad.CatchIO (catch)
import           Control.Monad.State
import           Control.Applicative
import           Control.Concurrent.MVar

import           Data.ByteString.UTF8 (ByteString)
import qualified Data.ByteString.UTF8 as B
import           Data.Maybe
import           Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import qualified Data.Text.Encoding.Error as T

import           Snap.Core
import           Snap.Snaplet
import           Snap.Snaplet.Auth
import           Snap.Snaplet.Auth.Backends.JsonFile
import           Snap.Snaplet.Heist
import           Snap.Snaplet.Session.Backends.CookieSession
import           Snap.Util.FileServe
import           Heist
import           Heist.Splices
import qualified Heist.Interpreted as I

import           Data.Time.Clock
import           Data.Time.LocalTime
import           Data.Time.Format

import           Data.Configurator
import           Data.Configurator.Types

import           System.Locale

import           System.Remote.Monitoring

------------------------------------------------------------------------------
import           Application
import           Utils
import           Types
import           Problem
import           Submission
import           LdapAuth
import           Printout

-- assoc lists of application handler splices
type Splices = [(Text, I.Splice AppHandler)]


------------------------------------------------------------------------------
-- | Handle login requests 
handleLogin :: AppHandler ()
handleLogin = method GET (with auth $ handleLoginForm Nothing) <|>
              method POST (do { user <- getRequiredParam "login"
                              ; passwd <- getRequiredParam "password"
                              ; ldapconf <- getLdapConf
                              ; with auth $ handleLoginSubmit ldapconf user passwd
                              })


-- | Render login form
handleLoginForm :: Maybe Text -> Handler App (AuthManager App) ()
handleLoginForm authError = heistLocal (I.bindSplices errs) $ render "login"
  where
    errs = [("loginError", I.textSplice c) | c <- maybeToList authError]


------------------------------------------------------------------------------
{-
-- | Handle login submit
handleLoginSubmit :: Handler App (AuthManager App) ()
handleLoginSubmit =
    loginUser "login" "password" Nothing
              (\_ -> handleLoginForm err) (redirect "/problems")
  where
    err = Just "Incorrect user or password"

-}

-- | Handle login submit using LDAP authentication
handleLoginSubmit :: LdapConf -> ByteString -> ByteString 
                     -> Handler App (AuthManager App) ()
handleLoginSubmit ldapConf user passwd = do
  optAuth <- withBackend (\r -> liftIO $ ldapAuth r ldapConf user passwd)
  case optAuth of 
    Nothing -> handleLoginForm err
    Just au -> forceLogin au >> redirect "/problems"
  where 
    err = Just "Utilizador ou password incorreto"


------------------------------------------------------------------------------
-- | Logs out and redirects the user to the site index.
handleLogout :: AppHandler ()
handleLogout = method GET $ do 
    uid <- getUser   --  ensure user is logged in   
    -- procedeed to printout in exam mode
    exam <- getConfigured "exam" False
    when exam $ handlePrintout uid
    with auth logout 
    redirect "/" 


------------------------------------------------------------------------------
-- | Handle new user form submit
{-
handleNewUser :: Handler App (AuthManager App) ()
handleNewUser = method GET handleForm <|> method POST handleFormSubmit
  where
    handleForm = render "register"
    handleFormSubmit = do
      login <- reqParam "login" 
      b <- usernameExists (T.pack $ B.toString login)
      if b then render "user_exists"
        else 
        registerUser "login" "password" >> redirect "/"
-}

-----------------------------------------------------------------------------
-- | Handle problem description request 
handleProblem :: AppHandler ()
handleProblem = method GET $ do
  uid <- getUser -- ensure a user is logged in
  pid <- PID <$> getRequiredParam "pid"
  prob <- liftIO $ getProblem pid
  -- check if problem is available and deny request if so
  t <- liftIO getCurrentTime
  when (not $ visible t prob) badRequest
  -- otherwise: show problem submissions
  subreps <- getSubmitReports uid prob 
  renderWithSplices "problem" (submissionsSplice subreps ++ 
                               pidSplice pid ++ 
                               problemSplices prob ++
                               numberSplices (length subreps) ++  
                               acceptedSplices (map (reportStatus.snd) subreps)) 


pidSplice :: PID -> Splices
pidSplice pid = [("problemid", I.textSplice (T.pack $ show pid))]


sidSplice :: SID -> Splices
sidSplice sid = [("submitid", I.textSplice (T.pack $ show sid))]


problemSplices :: Problem UTCTime -> Splices
problemSplices p = 
  [("problem",   I.textSplice (probTitle p)),
   ("description", return (probDescr p)),
   ("submitText", I.textSplice (probSubmit p)),
   ("startTime",   maybe (return []) timeSplice (probStart p)),
   ("endTime",     maybe (return []) timeSplice (probEnd p)),
   ("ifOpen", do t <- liftIO getCurrentTime
                 ifISplice (inside t (probStart p) (probEnd p))),
   ("ifBefore", do t <- liftIO getCurrentTime
                   ifISplice (fmap (t<) (probStart p) == Just True)),
   ("ifClosed", do t <- liftIO getCurrentTime
                   ifISplice (fmap (t>) (probEnd p) == Just True)),
   ("ifLimited", ifISplice (isJust $ probEnd p)),
   ("timeLeft", case probEnd p of 
       Nothing -> I.textSplice "N/A"
       Just t' -> do t <- liftIO getCurrentTime
                     I.textSplice $ T.pack $ formatNominalDiffTime $ diffUTCTime t' t)
  ]
  where
    -- convert UTC time to local time zone
    timeSplice t = do tz <- liftIO getCurrentTimeZone
                      I.textSplice $ T.pack $ 
                        formatTime defaultTimeLocale "%c" $ 
                        utcToZonedTime tz t


-- format a time difference
formatNominalDiffTime :: NominalDiffTime -> String
formatNominalDiffTime secs 
  | secs>=0  = unwords $ 
               [show d ++ "d" | d>0] ++ 
               [show (h`rem`24) ++ "h" | h>0] ++
               [show (m`rem`60) ++ "m" | m>0] ++
               ["<1m" | secs<60]
  | otherwise = "--/--"
  where m = round (secs / 60) :: Int
        h = (m `div` 60) 
        d = (h `div` 24)  
        




submitSplice :: Submission -> Splices
submitSplice s = [ ("submitText", I.textSplice (submitText s)) ]

submissionsSplice :: [(Submission,Report)] -> Splices
submissionsSplice lst
  = [("submissions", I.mapSplices (I.runChildrenWith . splices) lst)]
  where splices (s,r) = sidSplice (submitID s) ++ reportSplice r



-- | splices for a submission report
reportSplice :: Report -> [(Text, I.Splice AppHandler)]
reportSplice r =  [("status", I.textSplice (T.pack $ show $ reportStatus r)),
                   ("stdout", I.textSplice (reportStdout r)),
                   ("stderr", I.textSplice (reportStderr r)),
                   ("ifAccepted", ifISplice (s == Accepted)),
                   ("ifOverdue",  ifISplice (s == Overdue)),
                   ("ifRejected", ifISplice (s/= Accepted && s/=Overdue))
                   ]
  where s = reportStatus r


acceptedSplices :: [Status] -> Splices
acceptedSplices statuses 
  = [("ifAccepted", ifISplice b), ("ifNotAccepted", ifISplice (not b))]
  where b = any (==Accepted) statuses




handleProblemList :: AppHandler ()
handleProblemList = method GET $ do
  uid <- getUser
  -- filter currently available problems
  t <- liftIO getCurrentTime
  probs <- filter (visible t) <$> liftIO getProblems
  subrepss <- mapM (getSubmitReports uid) probs
  renderWithSplices "problemlist"  
    [("problemList", 
      I.mapSplices (I.runChildrenWith . splices) (zip probs subrepss))]
  where splices (prob,subreps) 
          = pidSplice (probID prob) ++ 
            problemSplices prob ++
            acceptedSplices (map (reportStatus.snd) subreps) ++
            numberSplices (length subreps)
            

-- splices concerning the number of submissions
numberSplices :: Int -> Splices
numberSplices n = [("numberOfSubmissions", I.textSplice (T.pack $ show n)),
                   ("ifSubmissions", ifISplice (n>0)),
                   ("ifNoSubmissions", ifISplice (n==0))
                  ]


handleGetSubmission, handlePostSubmission :: AppHandler ()
handleGetSubmission = method GET $ do
  uid <- getUser
  pid <- PID <$> getRequiredParam "pid"
  sid <- read . B.toString <$> getRequiredParam "sid"
  prob <- liftIO $ getProblem pid
  (sub,rep) <- getSubmitReport uid prob sid
  renderWithSplices "report" 
    (pidSplice pid ++ sidSplice sid ++  problemSplices prob ++ 
     submitSplice sub ++ reportSplice rep)

handlePostSubmission = method POST $ do
  uid <- getUser
  pid <-  PID <$> getRequiredParam "pid"
  prob <- liftIO $ getProblem pid
  incrCounter "submissions"
  code <- T.decodeUtf8With T.ignore <$> getRequiredParam "code"
  sid <- liftMutexIO $ newSubmitID uid pid code
  (sub,report) <- getSubmitReport uid prob sid
  renderWithSplices "report" (pidSplice pid ++ 
                              sidSplice sid ++ 
                              problemSplices prob ++ 
                              submitSplice sub ++ 
                              reportSplice report )


{-
-- handler for listing all submissions 
-- quick and dirty output routine 
handleSubmissions :: Handler App App ()
handleSubmissions = method GET $ do
  getUser    -- should be authenticated
  stats <- liftIO getAllStatus
  names <- with auth $ withBackend $ \r -> liftIO $ 
    sequence [lookup r txt | uid<-Map.keys stats, let txt=T.pack $ show uid]
  writeBS "UserID\tName\tAccepted\tSubmissions\n"
  sequence_ [ writeBS $ B.fromString $ 
              printf "%s\t%s\t%d\t%d\n" (show uid) (show name) accepts submits
            | ((uid, probs), name) <- zip (Map.assocs stats) names,
              let accepts = Map.size $ Map.filter (any (==Accepted)) probs,
              let submits = sum (Map.elems $ Map.map length probs)
            ]
  where 
    lookup r txt = do m<-lookupByLogin r txt
                      case m of Nothing -> return txt
                                Just au -> return (userName au)
-}

    


-- in exam mode show final report and confirm logout
-- otherwise, logout immediately
handleConfirmLogout :: AppHandler ()
handleConfirmLogout = do
  exam <- getConfigured "exam" False
  if exam then handleFinalReport else handleLogout

handleFinalReport :: AppHandler ()
handleFinalReport = method GET $ do
    uid <- getUser  
    probs <- liftIO getProblems
    subs <- sequence [getFinalReport uid p | p<-probs]
    let psubs = [(p,s,r) | (p, Just (s,r))<-zip probs subs]
    renderWithSplices "finalrep" 
      [("problemList", I.mapSplices (I.runChildrenWith . splices) psubs)]
  where splices (prob,sub,rep) = problemSplices prob ++ 
                                 acceptedSplices [reportStatus rep] ++
                                 reportSplice rep ++
                                 submitSplice sub



------------------------------------------------------------------------------
-- | The application's routes.
routes :: [(ByteString, AppHandler ())]
routes = [ ("/login",                 handleLogin `catch` internalError)
         , ("/logout",                handleLogout `catch` internalError)
         -- , ("/register", with auth handleNewUser)
         , ("/problems/:pid",         handleProblem `catch` internalError )
         , ("/problems",              handleProblemList `catch` internalError)
         -- , ("/submissions",        handleSubmissions `catch` internalError)
         , ("/submissions/:pid",      handlePostSubmission `catch` internalError)
         , ("/submissions/:pid/:sid", handleGetSubmission  `catch` internalError)
         , ("/asklogout",             handleConfirmLogout `catch` internalError)        
         , ("",                       serveDirectory "static" <|> notFound)
         ]




-- | current logged in full user name  
loggedInName :: SnapletLens b (AuthManager b) -> SnapletISplice b
loggedInName authmgr = do
    u <- lift $ withTop authmgr currentUser
    maybe (return []) (I.textSplice . userName) u 


-- | splice for current date & time
nowSplice :: I.Splice AppHandler
nowSplice = do t <- liftIO (getCurrentTime >>= utcToLocalZonedTime)
               I.textSplice (T.pack $ formatTime defaultTimeLocale "%c" t)

------------------------------------------------------------------------------
-- | The application initializer.
app :: SnapletInit App App
app = 
  makeSnaplet "pythondo" "Web system for learning Python programming." Nothing $ do
    conf <- getSnapletUserConfig
    ekg <- liftIO $ initEkg conf
    h <- nestSnaplet "" heist $ heistInit "templates"
    s <- nestSnaplet "sess" sess $
           initCookieSessionManager "site_key.txt" "sess" (Just 7200)

    -- NOTE: We're using initJsonFileAuthManager here because it's easy and
    -- doesn't require any kind of database server to run.  In practice,
    -- you'll probably want to change this to a more robust auth backend.
    a <- nestSnaplet "auth" auth $
           initJsonFileAuthManager defAuthSettings sess "users.json"
    addAuthSplices h auth
    addConfig h emptyConfig { hcInterpretedSplices = [("timeNow", nowSplice),
                                                      ("loggedInName", loggedInName auth)] }
    addRoutes routes
    mv <- liftIO $ newMVar ()
    return $ App h s a mv conf ekg 


-- initialize EKG server (if configured)
initEkg :: Config -> IO (Maybe Server)
initEkg conf = do enabled <- require conf "ekg.enabled"
                  if enabled then 
                    do host <- require conf "ekg.host"
                       port <- require conf "ekg.port"
                       Just <$> forkServer host port                   
                    else return Nothing
  



emptyConfig :: HeistConfig m
emptyConfig = HeistConfig [] [] [] [] []

