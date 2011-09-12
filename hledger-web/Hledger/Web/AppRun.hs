{-# LANGUAGE CPP #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module Hledger.Web.AppRun (
               withApp
              ,withDevelAppPort
              )
where

import Data.Dynamic (Dynamic, toDyn)
import Network.Wai (Application)
import Network.Wai.Middleware.Debug (debugHandle)
import Yesod.Logger (makeLogger, flushLogger, Logger, logLazyText, logString)
import Yesod.Static

import Hledger
import Hledger.Web.App
import Hledger.Web.Handlers
import Hledger.Web.Options
import Hledger.Web.Settings

-- This line actually creates our YesodSite instance. It is the second half
-- of the call to mkYesodData which occurs in App.hs. Please see
-- the comments there for more details.
mkYesodDispatch "App" resourcesApp

-- This function allocates resources (such as a database connection pool),
-- performs initialization and creates a WAI application. This is also the
-- place to put your migrate statements to have automatic database
-- migrations handled by Yesod.
withApp :: AppConfig -> Logger -> (Application -> IO a) -> IO a
withApp conf logger f = do
#ifdef PRODUCTION
    putStrLn $ "Production mode, using embedded web files"
    let s = $(embed Hledger.Web.Settings.staticDir)
#else
    putStrLn $ "Not in production mode, using web files from " ++ Hledger.Web.Settings.staticDir ++ "/"
    s <- staticDevel Hledger.Web.Settings.staticDir
#endif
    let a = App {settings=conf
                ,getLogger=logger
                ,getStatic=s
                ,appOpts=defwebopts
                ,appArgs=[]
                ,appJournal=nulljournal
                }
    toWaiApp a >>= f

-- for yesod devel
withDevelAppPort :: Dynamic
withDevelAppPort =
    toDyn go
  where
    go :: ((Int, Application) -> IO ()) -> IO ()
    go f = do
        conf <- Hledger.Web.Settings.loadConfig Hledger.Web.Settings.Development
        let port = appPort conf
        logger <- makeLogger
        logString logger $ "Devel application launched, listening on port " ++ show port
        withApp conf logger $ \app -> f (port, debugHandle (logHandle logger) app)
        flushLogger logger
      where
        logHandle logger msg = logLazyText logger msg >> flushLogger logger
