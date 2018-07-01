module Main where

import Prelude

import Control.Plus (empty)
import Data.Bifunctor (lmap)
import Data.Either (Either(..))
import Data.Foldable (oneOf)
import Data.Generic.Rep (class Generic)
import Data.Generic.Rep.Show (genericShow)
import Data.Maybe (Maybe(..))
import Database.Postgres (ClientConfig, ConnectionInfo, Query(Query), connectionInfoFromConfig, defaultPoolConfig, end, mkPool, query_, withClient) as Pg
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Console (log)
import Effect.Exception (error, Error)
import Foreign (Foreign)
import Foreign.Generic (encodeJSON)
import Models (User)
import Node.Encoding (Encoding(..))
import Node.HTTP (Request, Response, listen, createServer, setHeader, requestMethod, requestURL, responseAsStream, requestAsStream, setStatusCode)
import Node.Stream (Stream, Write, Writable, end, pipe, writeString)
import Partial.Unsafe (unsafeCrashWith)
import Routing (match)
import Routing.Match (Match, lit, nonempty, str)
import Simple.JSON as JSON


data PostRoutes
  = CustomerLogin Unit
  | CustomerSignup Unit

derive instance eqMyRoutes :: Eq PostRoutes
derive instance genericMyRoutes :: Generic PostRoutes _
instance showMyRoutes :: Show PostRoutes where show = genericShow

routing :: Match PostRoutes
routing = oneOf
  [ CustomerLogin <$> (lit "api/v1/customerlogin")
  , CustomerSignup <$> (lit "api/v1/customersignup")
  ]


handleCustomerLogin :: forall a. Request -> Response -> (Writable a) -> Effect Unit
handleCustomerLogin req res outStream = do
  pool <- Pg.mkPool connectionInfo

  launchAff_ $ Pg.withClient pool $ \conn -> do
    users <- Pg.query_ read' (Pg.Query "select * from users order by first_name desc" :: Pg.Query User) conn
    
    liftEffect $ log $ encodeJSON users

    liftEffect $ setHeader res "Content-Type" "text/plain"
    _ <- liftEffect $ writeString outStream UTF8 (encodeJSON users) (pure unit)
    liftEffect $ end outStream (pure unit)
  
  Pg.end pool


main :: Effect Unit
main = do
  log "Hello sailor!"

  app <- createServer router
  listen app { hostname: "localhost", port: 8080, backlog: Nothing } $ void do
    log "Server setup done!"
    log "Listening on port 8080."


router :: Request -> Response -> Effect Unit
router req res = do
  setStatusCode res 200

  let inputStream  = requestAsStream req
      outputStream = responseAsStream res
  log (requestMethod req <> " " <> requestURL req)

  case requestMethod req of
    -- "GET" -> do
    --   handleCustomerLogin req res outputStream
    -- "POST" -> void $ pipe inputStream outputStream

    "GET" -> do
      handleCustomerLogin req res outputStream
    "POST" -> 
      -- handleCustomerLogin req res outputStream
    -- log $ show $ (match routing (requestURL req))

    case (match routing (requestURL req)) of 
      Right (CustomerLogin _) -> 
        handleCustomerLogin req res outputStream
      _ -> void $ pipe inputStream outputStream
    _ -> unsafeCrashWith "Unexpected HTTP method"


clientConfig :: Pg.ClientConfig
clientConfig =
  { host: "localhost"
  , database: "mychangedb"
  , port: 5432
  , user: "postgres"
  , password: "asdffdsa"
  , ssl: false
  }

connectionInfo :: Pg.ConnectionInfo
connectionInfo = Pg.connectionInfoFromConfig clientConfig Pg.defaultPoolConfig

read' :: forall a. JSON.ReadForeign a => Foreign -> Either Error a
read' = lmap (error <<< show) <<< JSON.read