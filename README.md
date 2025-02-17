# Workout Tracker

Simple full stack web app for tracking workouts.

## Demo

A live demo of the app is hosted [here](https://workout-demo.pierre-dev.com).
It is "secured" with the basic auth credentials "demo" "demo". The data entered
there is reset on a daily basis. The demo might be taken offline at any point in
the future without updating the readme. The main pages (landing page and workout
page) look like this:

<img src="https://github.com/xddq/workout-tracker/blob/main/landing-page.png">
<img src="https://github.com/xddq/workout-tracker/blob/main/workout-page.png">

## Learnings

- We can use smart constructors to enforce validation logic when trying to
  create a type. See usage of mkExercise for an example of this.
- We can encode knowledge in types (e.g. NonEmpty [a]) in order to avoid doing
  the same check (list is not empty).
- We can short circuit execution by matching on a constructor (e.g. see DB.hs
  `Right exercises <- getExercisesForWorkout conn $ exerciseWorkoutId x`). If
the result is not a Right x the code short circuits by returning the resulting
Left.
- Error/Exception handling. After asking why postgresql-simple does throw
  exceptions instead of use Either for modelling them, I got told that most
Haskell libraries make tradeoffs in beginner friendlyness (in the form of low/no
stacking of monads) and error/exception handling. For example the query function
in postgresql-simple which is used to query the database returns IO [r] where r
is assumed to be the data type you are handling with a FromJson and ToJson
instance. E.g. Exercise or Workout for this app. See [query documentation
here](https://hackage.haskell.org/package/postgresql-simple-0.7.0.0/docs/Database-PostgreSQL-Simple.html#g:15).
I would expect/prefer a return type of IO (Either Text r) which means that we
have error/exception handling baked in and not as an afterthought. I don't know
how common this is, but this is what I adapted the DB module to and currently
prefer. I got around this by creating a custom exception handler and wrapping
the database calls with this wrapper. E.g. see
'unsafeDeleteWorkoutWithExercises' and 'deleteWorkoutWithExercises'.

# Prerequisites

- Ensure you have ghc and cabal installed. I used
  [ghcup](https://www.haskell.org/ghcup/) to get these and used ghc 9.2.7 and
  cabal version 3.6.2.0.
- dbmate installed for raw SQL migrations
  - [install docs](https://github.com/amacneil/dbmate#installation)
- docker and docker-compose installed
- libpq-dev installed (for ubuntu 20.04 run `apt install libpq-dev`) I think
  this was required to be able to build postgresql-simple..?

## Quickstart

- Set up environment variables `cp env.local .env`
- Start postgresql/database `docker-compose up -d`
- Create the database `dbmate create`
- Create the tables for our app `dbmate up`
- Install dependencies and build the app `cabal build`
- Run the app `cabal run app`
- Browse http://localhost:3000 to use the app
- For development it might be useful to run `bash watch-and-rebuild.sh` if you
  have inotify-watch installed it will then automatically rebuild whenever you
  make and save changes to the app.

## Managing the database

- [dbmate](https://github.com/amacneil/dbmate) is used for migrations, check
  their docu there if in doubt.
- Run dbmate to create migrations. Use snake_case since this is the default for
  postgres and dbmate. E.g. `dbmate new add_origin_created_at_to_recipes`
- A file will created which looks like this

```

-- migrate:up


-- migrate:down

```

## Hosting the app

I would suggest to host this app behind basic auth with secure credentials.
For the deployment, my automated deployment setup for GitLab can be found under
./.gitlab-ci.yml. I simply have a nginx reverse proxy in front of the app
secured with basic auth.

## Improvements

Happy about suggestions and improvements to the small code base. If you find
something confusing about "todo-app" in this code it is because I started with
the previous small project
[haskell-simple-todo](https://github.com/xddq/haskell-simple-todo) as baseline
and did not bother to adapt it in all places.
