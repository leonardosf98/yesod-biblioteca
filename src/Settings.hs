{-# LANGUAGE CPP               #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE TemplateHaskell   #-}
module Settings where

import           ClassyPrelude.Yesod
import qualified Control.Exception           as Exception
import           Data.Aeson                  (withObject, (.!=), (.:?))
import           Data.FileEmbed              (embedFile)
import           Data.Yaml                   (decodeEither')
import           Database.Persist.Postgresql (PostgresConf)
import           Network.Wai.Handler.Warp    (HostPreference)
import           Yesod.Default.Config2       (configSettingsYml)

data AppSettings = AppSettings
    { appDatabaseConf           :: PostgresConf
    , appRoot                   :: Maybe Text
    , appHost                   :: HostPreference
    , appPort                   :: Int
    , appIpFromHeader           :: Bool
    , appDetailedRequestLogging :: Bool
    , appShouldLogAll           :: Bool
    }

instance FromJSON AppSettings where
    parseJSON = withObject "AppSettings" $ \o -> do
        let defaultDev =
#ifdef DEVELOPMENT
                True
#else
                False
#endif
        appDatabaseConf           <- o .: "database"
        appRoot                   <- o .:? "approot"
        appHost                   <- fromString <$> o .: "host"
        appPort                   <- o .: "port"
        appIpFromHeader           <- o .: "ip-from-header"
        dev                       <- o .:? "development"      .!= defaultDev
        appDetailedRequestLogging <- o .:? "detailed-logging" .!= dev
        appShouldLogAll           <- o .:? "should-log-all"   .!= dev
        return AppSettings {..}

configSettingsYmlBS :: ByteString
configSettingsYmlBS = $(embedFile configSettingsYml)

configSettingsYmlValue :: Value
configSettingsYmlValue = either Exception.throw id $ decodeEither' configSettingsYmlBS
