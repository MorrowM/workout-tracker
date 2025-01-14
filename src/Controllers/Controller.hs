{-# LANGUAGE OverloadedStrings #-}

module Controllers.Controller (readWorkout, updateWorkout, deleteWorkout, orderWorkoutExercises, apiCreateWorkout, apiUpdateWorkout, apiDeleteWorkout, updateExercise, deleteExercise, apiCreateExercise, apiUpdateExercises, apiUpdateExercise, apiDeleteExercise, displayPage, customErrorHandler, landingPage) where

import Control.Monad.IO.Class (MonadIO (liftIO))
import Controllers.Exercise (apiCreateExercise, apiDeleteExercise, apiUpdateExercise, apiUpdateExercises, deleteExercise, updateExercise)
import Controllers.Util (displayPage)
import Controllers.Workout (apiCreateWorkout, apiDeleteWorkout, apiUpdateWorkout, deleteWorkout, orderWorkoutExercises, readWorkout, updateWorkout)
import Data.Text.Lazy (Text, split, unpack)
import Data.Time (Day, UTCTime (utctDay), defaultTimeLocale, formatTime, getCurrentTime, parseTimeM)
import qualified Database.DB as DB
import Database.PostgreSQL.Simple (Connection)
import Network.HTTP.Types (status400)
import qualified Views.Page as Views
import Web.Scotty (ActionM, param, rescue, status)

customErrorHandler :: Text -> ActionM ()
customErrorHandler err = do
  status status400
  displayPage $ Views.errorPage err

landingPage :: Connection -> ActionM ()
landingPage conn = do
  success <- param "success" `rescue` (\_ -> return False)
  currentDate <- liftIO (utctDay <$> getCurrentTime)
  workoutsEither <- liftIO (DB.getWorkouts conn)
  displayPage $ Views.landingPage success (Views.mkCurrentDate currentDate) workoutsEither
