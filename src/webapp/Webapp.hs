{-# LANGUAGE OverloadedStrings #-}

module Webapp (mkApp) where

import Control.Monad.Cont (MonadIO (liftIO))
import Data.Aeson (FromJSON (parseJSON), Result (Error, Success), ToJSON (toJSON), Value, decode, encode, fromJSON, object, withObject, (.:), (.=))
import Data.Either (fromLeft, isLeft)
import Data.List (sortOn)
import Data.Maybe (fromJust, isJust, listToMaybe)
import Data.String (IsString (fromString))
import Data.Text.Lazy (Text, null, pack, split, unpack)
import qualified Data.Text.Lazy as T
import Data.Text.Lazy.Encoding (decodeUtf8)
import Data.Text.Lazy.Read (decimal)
import Data.Time (Day, UTCTime (utctDay), defaultTimeLocale, formatTime, getCurrentTime, parseTimeM)
import Database (CreateExerciseInput (CreateExerciseInput), CreateWorkoutInput (CreateWorkoutInput), Exercise (Exercise, exerciseWorkoutId), Workout (Workout, workoutId), createExercise, createWorkout, deleteExerciseById, deleteWorkoutWithExercises, getExerciseById, getExercisesForWorkout, getHighestPositionByWorkoutId, getWorkoutById, getWorkouts, updateExercise, updatePositionOfExercise, updatePositionsOfExercises, updateWorkout)
import Database.PostgreSQL.Simple (Connection)
import Database.PostgreSQL.Simple.Types (PGArray (PGArray))
import GHC.Generics (Generic)
import Network.HTTP.Types (Status, status200, status400, status404, status500)
import Network.Wai (Application)
import Network.Wai.Middleware.Cors (CorsResourcePolicy (corsMethods, corsRequestHeaders), cors, simpleCorsResourcePolicy)
import Network.Wai.Middleware.RequestLogger (logStdoutDev)
import Network.Wai.Middleware.Static (addBase, staticPolicy)
import Text.Blaze.Html (Html)
import Text.Read (readMaybe)
import Views (deleteExercisePage, deleteWorkoutPage, editExercisePage, editWorkoutPage, errorPage, htmlToText, landingPage, mkCurrentDate, showOrderExercisesPage, showWorkoutPage, successPage)
import Web.Scotty (ActionM, Param, Parsable (parseParam), body, delete, get, html, middleware, param, params, patch, post, redirect, rescue, scottyApp, setHeader, status, text)

-- days may have 1 or 2 chars, then one space, then month with one or two
-- letters then space and a 4 char year. Example: 23 07 2023
dateFormat :: String
dateFormat = "%-d.%-m.%Y"

textToDate :: String -> Maybe Day
textToDate = parseTimeM True defaultTimeLocale dateFormat

euroToCent :: Double -> Int
euroToCent x = round $ x * 100

displayPage :: Html -> ActionM ()
displayPage x = do
  setHeader "Content-Type" "text/html; charset=utf-8"
  text $ htmlToText x

mkApp :: Connection -> IO Application
mkApp conn =
  scottyApp $ do
    -- Add any WAI middleware, they are run top-down.
    -- log all requests in console
    middleware logStdoutDev
    -- serve static files from the "static" directory
    middleware $ staticPolicy (addBase "static")

    -- ability to create workout and display previous ones
    get "/" $ do
      success <- param "success" `rescue` (\_ -> return False)
      currentDate <- liftIO (utctDay <$> getCurrentTime)
      workouts <- liftIO (getWorkouts conn)
      displayPage $ landingPage success (mkCurrentDate currentDate) workouts

    -- edit workout (just type and date)
    get "/workouts/:id/edit" $ do
      unparsedId <- param "id"
      case decimal unparsedId of
        Left err -> text $ htmlToText (errorPage $ pack err)
        Right (parsedId, _rest) -> do
          workoutList <- liftIO (getWorkoutById conn parsedId)
          case listToMaybe workoutList of
            Just x -> displayPage $ editWorkoutPage x
            Nothing -> displayPage $ errorPage "not found"

    -- display exercises of the workout (also able to edit them)
    get "/workouts/:id/show" $ do
      unparsedId <- param "id"
      success <- param "success" `rescue` (\_ -> return False)
      case decimal unparsedId of
        Left err -> text $ htmlToText (errorPage $ pack err)
        Right (parsedId, _rest) -> do
          workoutList <- liftIO (getWorkoutById conn parsedId)
          case listToMaybe workoutList of
            Just workout -> do
              exercises <- liftIO (getExercisesForWorkout conn (workoutId workout))
              displayPage $ showWorkoutPage success workout exercises
            Nothing -> displayPage $ errorPage "not found"

    get "/workouts/:id/delete" $ do
      unparsedId <- param "id"
      case decimal unparsedId of
        Left err -> text $ htmlToText (errorPage $ pack err)
        Right (parsedId, _rest) -> do
          workouts <- liftIO (getWorkoutById conn parsedId)
          case listToMaybe workouts of
            Nothing -> displayPage $ errorPage "not found"
            Just workout -> displayPage $ deleteWorkoutPage workout

    get "/workouts/:id/exercises/order" $ do
      workoutId <- param "id" :: ActionM Int
      exercises <- liftIO (getExercisesForWorkout conn workoutId)
      displayPage $ showOrderExercisesPage exercises

    get "/exercises/:id/delete" $ do
      unparsedId <- param "id"
      case decimal unparsedId of
        Left err -> text $ htmlToText (errorPage $ pack err)
        Right (parsedId, _rest) -> do
          exerciseList <- liftIO (getExerciseById conn parsedId)
          case listToMaybe exerciseList of
            Nothing -> displayPage $ errorPage "not found"
            Just x -> displayPage $ deleteExercisePage x

    get "/exercises/:id/edit" $ do
      unparsedId <- param "id"
      case decimal unparsedId of
        Left err -> text $ htmlToText (errorPage $ pack err)
        Right (parsedId, _rest) -> do
          exerciseList <- liftIO (getExerciseById conn parsedId)
          case listToMaybe exerciseList of
            Just x -> displayPage $ editExercisePage x
            Nothing -> displayPage $ errorPage "not found"

    -- expecting the form params here in order to create the new entry
    -- TODO: use the prefillWorkoutId to create workout with given exercises!
    -- also use the type of the prefillWorkout for the new workout.
    post "/api/create-workout" $ do
      workoutType <- param "type" :: ActionM Text
      workoutId <- param "prefillWorkoutId" :: ActionM Int
      workoutDate <- param "date" :: ActionM String
      case textToDate workoutDate of
        Nothing -> displayPage $ errorPage "could not parse the given date"
        Just date -> do
          createdWorkout <- liftIO $ createWorkout conn (CreateWorkoutInput (if T.null workoutType then "Keine Angabe" else workoutType) date workoutId)
          if isJust createdWorkout then redirect ("/" <> "?success=true") else displayPage $ errorPage "error creating workout"

    post "/api/create-exercise" $ do
      title <- param "title" :: ActionM Text
      unparsedReps <- param "reps" :: ActionM Text
      note <- param "note" :: ActionM Text
      unparsedWeights <- param "weightsInKg" :: ActionM Text
      workoutId <- param "workoutId" :: ActionM Int
      case parseReps unparsedReps of
        Just reps -> do
          case parseWeights unparsedWeights of
            Nothing -> displayPage $ errorPage "error parsing the weights"
            Just weights -> do
              position <- liftIO $ getHighestPositionByWorkoutId conn workoutId
              case position of
                Left err -> displayPage $ errorPage err
                Right position -> do
                  createdExercise <- liftIO $ createExercise conn (CreateExerciseInput title (PGArray reps) note position workoutId (PGArray weights))
                  either
                    (displayPage . errorPage)
                    (\x -> redirect ("/workouts/" <> pack (show $ exerciseWorkoutId x) <> "/show?success=true"))
                    createdExercise
        Nothing -> displayPage $ errorPage "error parsing the reps"

    -- bulk updates exercises, used for updating their position/order
    post "/api/update-exercises" $ do
      -- we pass position(first) exerciseId(second) multiple times (once per
      -- exercise) and read them out via 'params'.
      positions <- params
      let exercisePositionTuples = ensureAscendingPositions $ parsePositionExerciseIdTuples positions
       in do
            result <- liftIO $ updatePositionsOfExercises conn exercisePositionTuples
            case result of
              Just _ -> do
                -- NOTE: could just pass the 'workoutId' via path or also post
                -- param. For now just query for the workoutId of any given
                -- exercise (all belong to the same exercise).
                exerciseList <- liftIO $ getExerciseById conn $ snd $ head exercisePositionTuples
                case listToMaybe exerciseList of
                  Just exercise -> redirect ("/workouts/" <> pack (show $ exerciseWorkoutId exercise) <> "/show?success=true")
                  Nothing -> displayPage $ errorPage "error getting the exercise for a given exerciseId"
              Nothing -> displayPage $ errorPage "error updating the exercises"

    post "/api/update-exercise" $ do
      id <- param "id" :: ActionM Int
      title <- param "title" :: ActionM Text
      unparsedReps <- param "reps" :: ActionM Text
      note <- param "note" :: ActionM Text
      position <- param "position" :: ActionM Int
      unparsedWeights <- param "weightsInKg" :: ActionM Text
      workoutId <- param "workoutId" :: ActionM Int
      case parseReps unparsedReps of
        Just reps -> do
          case parseWeights unparsedWeights of
            Nothing -> displayPage $ errorPage "could not parse the given weights"
            Just weights -> do
              updatedExercise <- liftIO $ updateExercise conn (Exercise id title (PGArray reps) note position workoutId (PGArray weights))
              either
                (\err -> displayPage $ errorPage $ "error creating exercise. error: " <> err)
                (\x -> redirect ("/workouts/" <> pack (show $ exerciseWorkoutId x) <> "/show?success=true"))
                updatedExercise
        Nothing -> displayPage $ errorPage "could not parse the given reps"

    post "/api/delete-exercise" $ do
      id <- param "id" :: ActionM Int
      title <- param "title" :: ActionM Text
      unparsedReps <- param "reps" :: ActionM Text
      note <- param "note" :: ActionM Text
      position <- param "position" :: ActionM Int
      unparsedWeights <- param "weightsInKg" :: ActionM Text
      workoutId <- param "workoutId" :: ActionM Int
      case parseReps unparsedReps of
        Nothing -> displayPage $ errorPage "could not parse the given reps"
        Just reps -> do
          case parseWeights unparsedWeights of
            Nothing -> displayPage $ errorPage "could not parse the given weights"
            Just weights -> do
              deletedExercise <- liftIO $ deleteExerciseById conn (Exercise id title (PGArray reps) note position workoutId (PGArray weights))
              case deletedExercise of
                Just x -> redirect ("/workouts/" <> pack (show workoutId) <> "/show?success=true")
                Nothing -> displayPage $ errorPage "error deleting exercise"

    post "/api/update-workout" $ do
      workoutId <- param "id" :: ActionM Int
      workoutType <- param "type" :: ActionM Text
      workoutDate <- param "date" :: ActionM String
      case textToDate workoutDate of
        Nothing -> displayPage $ errorPage "could not parse the given date"
        Just date -> do
          _updatedItem <- liftIO $ updateWorkout conn (Workout workoutId workoutType date)
          displayPage successPage

    post "/api/delete-workout" $ do
      id <- param "workoutId" :: ActionM Int
      deletedRowsCount <- liftIO $ deleteWorkoutWithExercises conn id
      either
        (displayPage . errorPage)
        (\_ -> redirect ("/" <> "?success=true"))
        deletedRowsCount

parseReps :: Text -> Maybe [Int]
parseReps x =
  mapM textToInt $ split (== ',') x
  where
    textToInt x = readMaybe (unpack x) :: Maybe Int

parseWeights :: Text -> Maybe [Int]
parseWeights = parseReps

-- TODO: later use newtype wrapper
type Position = Int

type ExerciseId = Int

-- Ensures that exercise positions start with 1 and that every exercise with a
-- given position N has a subsequent position N+1 (or it is the last item of the
-- list :p).
ensureAscendingPositions :: [(Position, ExerciseId)] -> [(Position, ExerciseId)]
ensureAscendingPositions xs = zipWith (\newPosition (_, exerciseId) -> (newPosition, exerciseId)) [1 ..] (sortOn fst xs)

parsePositionExerciseIdTuples :: [Param] -> [(Position, ExerciseId)]
parsePositionExerciseIdTuples ((position, pValue) : (exerciseId, eValue) : xs) = (toInt pValue, toInt eValue) : parsePositionExerciseIdTuples xs
  where
    toInt x = read $ unpack x :: Int
parsePositionExerciseIdTuples [] = []
