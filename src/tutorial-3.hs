{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE FlexibleInstances  #-}
{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeApplications   #-}
{-# LANGUAGE TypeFamilies       #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
module Tutorial3 where

import           Control.Lens
import           Data.Text                                (Text)
import           Data.Time
import           Database.Beam                            as B
import           Database.Beam.Backend
import           Database.Beam.Backend.SQL.BeamExtensions
import           Database.Beam.Postgres
import           Database.PostgreSQL.Simple
import           Database.PostgreSQL.Simple.FromField
import           Database.Beam.Backend.SQL
import           Text.Read

data UserT f = User
  { _userEmail     :: Columnar f Text
  , _userFirstName :: Columnar f Text
  , _userLastName  :: Columnar f Text
  , _userPassword  :: Columnar f Text
  } deriving (Generic)

type User = UserT Identity
type UserId = PrimaryKey UserT Identity

deriving instance Show User

instance Beamable UserT
instance Beamable (PrimaryKey UserT)

instance Table UserT where
  data PrimaryKey UserT f = UserId (Columnar f Text) deriving Generic
  primaryKey = UserId . _userEmail

data AddressT f = Address
  { _addressId      :: C f (Auto Int)
  , _addressLine1   :: C f Text
  , _addressLine2   :: C f (Maybe Text)
  , _addressCity    :: C f Text
  , _addressState   :: C f Text
  , _addressZip     :: C f Text
  , _addressForUser :: PrimaryKey UserT f
  } deriving (Generic)

type Address = AddressT Identity
type AddressId = PrimaryKey AddressT Identity

deriving instance Show UserId
deriving instance Show Address

instance Beamable AddressT
instance Beamable (PrimaryKey AddressT)

instance Table AddressT where
    data PrimaryKey AddressT f = AddressId (Columnar f (Auto Int)) deriving Generic
    primaryKey = AddressId . _addressId

data ProductT f = Product
  { _productId          :: C f (Auto Int)
  , _productTitle       :: C f Text
  , _productDescription :: C f Text
  , _productPrice       :: C f Int {- Price in cents -}
  } deriving (Generic)

type Product = ProductT Identity
type ProductId = PrimaryKey ProductT Identity

deriving instance Show Product

instance Table ProductT where
  data PrimaryKey ProductT f = ProductId (Columnar f (Auto Int)) deriving Generic
  primaryKey = ProductId . _productId

instance Beamable ProductT
instance Beamable (PrimaryKey ProductT)

deriving instance Show (PrimaryKey AddressT Identity)

data OrderT f = Order
  { _orderId            :: Columnar f (Auto Int)
  , _orderDate          :: Columnar f LocalTime
  , _orderForUser       :: PrimaryKey UserT f
  , _orderShipToAddress :: PrimaryKey AddressT f
  , _orderShippingInfo  :: PrimaryKey ShippingInfoT (Nullable f)
  } deriving (Generic)

type Order = OrderT Identity
deriving instance Show Order

instance Table OrderT where
    data PrimaryKey OrderT f = OrderId (Columnar f (Auto Int))
                               deriving Generic
    primaryKey = OrderId . _orderId

instance Beamable OrderT
instance Beamable (PrimaryKey OrderT)

data ShippingCarrier
  = USPS
  | FedEx
  | UPS
  | DHL
  deriving (Show, Read, Eq, Ord, Enum)

data ShippingInfoT f = ShippingInfo
  { _shippingInfoId             :: Columnar f (Auto Int)
  , _shippingInfoCarrier        :: Columnar f ShippingCarrier
  , _shippingInfoTrackingNumber :: Columnar f Text
  } deriving (Generic)

type ShippingInfo = ShippingInfoT Identity
deriving instance Show ShippingInfo

instance Table ShippingInfoT where
    data PrimaryKey ShippingInfoT f = ShippingInfoId (Columnar f (Auto Int))
                                      deriving Generic
    primaryKey = ShippingInfoId . _shippingInfoId

instance Beamable ShippingInfoT
instance Beamable (PrimaryKey ShippingInfoT)
deriving instance Show (PrimaryKey ShippingInfoT (Nullable Identity))

deriving instance Show (PrimaryKey OrderT Identity)
deriving instance Show (PrimaryKey ProductT Identity)

data LineItemT f = LineItem
  { _lineItemInOrder    :: PrimaryKey OrderT f
  , _lineItemForProduct :: PrimaryKey ProductT f
  , _lineItemQuantity   :: Columnar f Int
  } deriving (Generic)

type LineItem = LineItemT Identity
deriving instance Show LineItem

instance Table LineItemT where
    data PrimaryKey LineItemT f = LineItemId (PrimaryKey OrderT f) (PrimaryKey ProductT f)
                                  deriving Generic
    primaryKey = LineItemId <$> _lineItemInOrder <*> _lineItemForProduct

instance Beamable LineItemT
instance Beamable (PrimaryKey LineItemT)

data ShoppingCartDb f = ShoppingCartDb
  { _shoppingCartUsers         :: f (TableEntity UserT)
  , _shoppingCartUserAddresses :: f (TableEntity AddressT)
  , _shoppingCartProducts      :: f (TableEntity ProductT)
  , _shoppingCartOrders        :: f (TableEntity OrderT)
  , _shoppingCartShippingInfos :: f (TableEntity ShippingInfoT)
  , _shoppingCartLineItems     :: f (TableEntity LineItemT)
  } deriving (Generic)

instance Database ShoppingCartDb

instance HasSqlValueSyntax be String => HasSqlValueSyntax be ShippingCarrier where
  sqlValueSyntax = autoSqlValueSyntax

instance FromField ShippingCarrier where
  fromField f bs = do x <- readMaybe <$> fromField f bs
                      case x of
                        Nothing -> returnError ConversionFailed f "Could not 'read' value for 'ShippingCarrier'"
                        Just x -> pure x

instance FromBackendRow Postgres ShippingCarrier

shoppingCartDb :: DatabaseSettings be ShoppingCartDb
shoppingCartDb =
  defaultDbSettings `withDbModification`
  dbModification
  { _shoppingCartUserAddresses =
      modifyTable (\_ -> "addresses") $
      tableModification
      { _addressLine1 = fieldNamed "address1"
      , _addressLine2 = fieldNamed "address2"
      }
  , _shoppingCartProducts = modifyTable (\_ -> "products") tableModification
  , _shoppingCartOrders =
      modifyTable (\_ -> "orders") $
      tableModification
      {_orderShippingInfo = ShippingInfoId "shipping_info__id"}
  , _shoppingCartShippingInfos =
      modifyTable (\_ -> "shipping_info") $
      tableModification
      { _shippingInfoId = "id"
      , _shippingInfoCarrier = "carrier"
      , _shippingInfoTrackingNumber = "tracking_number"
      }
  , _shoppingCartLineItems = modifyTable (\_ -> "line_items") tableModification
  }

LineItem _ _ (LensFor lineItemQuantity) = tableLenses

Product (LensFor productId)          (LensFor productTitle)
        (LensFor productDescription) (LensFor productPrice) = tableLenses


Address (LensFor addressId)    (LensFor addressLine1)
        (LensFor addressLine2) (LensFor addressCity)
        (LensFor addressState) (LensFor addressZip)
        (UserId (LensFor addressForUserId)) = tableLenses

User (LensFor userEmail)    (LensFor userFirstName)
     (LensFor userLastName) (LensFor userPassword) = tableLenses

ShoppingCartDb (TableLens shoppingCartUsers) (TableLens shoppingCartUserAddresses)
               (TableLens shoppingCartProducts) (TableLens shoppingCartOrders)
               (TableLens shoppingCartShippingInfos) (TableLens shoppingCartLineItems) = dbLenses

allUsers :: Q PgSelectSyntax ShoppingCartDb s (UserT (QExpr PgExpressionSyntax s))
allUsers = all_ (shoppingCartDb ^. shoppingCartUsers)

allAddresses :: Q PgSelectSyntax ShoppingCartDb s (AddressT (QExpr PgExpressionSyntax s))
allAddresses = all_ (shoppingCartDb ^. shoppingCartUserAddresses)

users :: [User]
users@[james, betty, sam] = [ User "james@example.com" "James" "Smith" "b4cc344d25a2efe540adbf2678e2304c"
                            , User "betty@example.com" "Betty" "Jones" "82b054bd83ffad9b6cf8bdb98ce3cc2f"
                            , User "sam@example.com" "Sam" "Taylor" "332532dcfaa1cbf61e2a266bd723612c"]

addresses :: [Address]
addresses = [ Address (Auto Nothing) "123 Little Street" Nothing "Boston" "MA" "12345" (pk james)
            , Address (Auto Nothing) "222 Main Street" (Just "Ste 1") "Houston" "TX" "8888" (pk betty)
            , Address (Auto Nothing) "9999 Residence Ave" Nothing "Sugarland" "TX" "8989" (pk betty)
            ]

products :: [Product]
products = [ Product (Auto Nothing) "Red Ball" "A bright red, very spherical ball" 1000
           , Product (Auto Nothing) "Math Textbook" "Contains a lot of important math theorems and formulae" 2500
           , Product (Auto Nothing) "Intro to Haskell" "Learn the best programming language in the world" 3000
           , Product (Auto Nothing) "Suitcase" "A hard durable suitcase" 15000
           ]

shippingInfos :: [ShippingInfo]
shippingInfos = [ ShippingInfo (Auto Nothing) USPS "12345790ABCDEFGHI" ]

insertUsers :: Connection -> IO ()
insertUsers conn =
  withDatabaseDebug putStrLn conn $ B.runInsert $
    B.insert (_shoppingCartUsers shoppingCartDb) $
    insertValues users

insertAddresses :: Connection -> IO [Address]
insertAddresses conn =
  withDatabaseDebug putStrLn conn $
    runInsertReturningList (shoppingCartDb ^. shoppingCartUserAddresses) $
    insertValues addresses

insertShippingInfos :: Connection -> IO [ShippingInfo]
insertShippingInfos conn =
 withDatabaseDebug putStrLn conn $
  runInsertReturningList (shoppingCartDb ^. shoppingCartShippingInfos) $
  insertValues shippingInfos

insertProducts :: Connection -> IO [Product]
insertProducts conn =
  withDatabaseDebug putStrLn conn $
    runInsertReturningList (shoppingCartDb ^. shoppingCartProducts) $
    insertValues products

insertOrders :: Connection -> [Address] -> ShippingInfo -> IO [Order]
insertOrders conn [jamesAddress1, bettyAddress1, bettyAddress2] bettyShippingInfo =
  do
    time <- getCurrentTime
    let localtime = utcToLocalTime utc time
    withDatabaseDebug putStrLn conn $
      runInsertReturningList (shoppingCartDb ^. shoppingCartOrders) $
      insertValues [ Order (Auto Nothing) localtime (pk james) (pk jamesAddress1) nothing_
                   , Order (Auto Nothing) localtime (pk betty) (pk bettyAddress1) (just_ (pk bettyShippingInfo))
                   , Order (Auto Nothing) localtime (pk james) (pk jamesAddress1) nothing_
                   ]

insertLineItems :: Connection -> [Order] -> [Product] -> IO ()
insertLineItems conn orders@[jamesOrder1, bettyOrder1, jamesOrder2] products@[redBall, mathTextbook, introToHaskell, suitcase] =
  withDatabaseDebug putStrLn conn $
  B.runInsert $ B.insert (shoppingCartDb ^. shoppingCartLineItems) $
  insertValues [ LineItem (pk jamesOrder1) (pk redBall) 10
               , LineItem (pk jamesOrder1) (pk mathTextbook) 1
               , LineItem (pk jamesOrder1) (pk introToHaskell) 4
               , LineItem (pk bettyOrder1) (pk mathTextbook) 3
               , LineItem (pk bettyOrder1) (pk introToHaskell) 3
               , LineItem (pk jamesOrder2) (pk mathTextbook) 1 ]

selectAllUsers :: Connection -> IO ()
selectAllUsers conn =
  withDatabaseDebug putStrLn conn $ do
    users <- runSelectReturningList $ select allUsers
    mapM_ (liftIO . putStrLn . show) users

selectAllUsersAndAddresses :: Connection -> IO ([(User, Address)])
selectAllUsersAndAddresses conn =
  withDatabaseDebug putStrLn conn $ runSelectReturningList $ select $ do
    address <- allAddresses
    user <- related_ (shoppingCartDb ^. shoppingCartUsers) (_addressForUser address)
    return (user, address)

selectAllUsersAndOrdersLeftJoin :: Connection -> IO [(User, Maybe Order)]
selectAllUsersAndOrdersLeftJoin conn =
  withDatabaseDebug putStrLn conn $
      runSelectReturningList $ select $ do
        user  <- all_ (shoppingCartDb ^. shoppingCartUsers)
        order <- leftJoin_ (all_ (shoppingCartDb ^. shoppingCartOrders)) (\order -> _orderForUser order `references_` user)
        pure (user, order)

selectUsersWithNoOrdersLeftJoin :: Connection -> IO [User]
selectUsersWithNoOrdersLeftJoin conn =
   withDatabaseDebug putStrLn conn $
    runSelectReturningList $ select $ do
      user  <- all_ (shoppingCartDb ^. shoppingCartUsers)
      order <- leftJoin_ (all_ (shoppingCartDb ^. shoppingCartOrders)) (\order -> _orderForUser order `references_` user)
      guard_ (isNothing_ order)
      pure user

selectUsersWithNoOrdersExistsCombinator :: Connection -> IO [User]
selectUsersWithNoOrdersExistsCombinator conn =
   withDatabaseDebug putStrLn conn $
    runSelectReturningList $ select $ do
      user  <- all_ (shoppingCartDb ^. shoppingCartUsers)
      guard_ (not_ (exists_ (filter_ (\order -> _orderForUser order `references_` user) (all_ (shoppingCartDb ^. shoppingCartOrders)))))
      pure user

ordersWithCostOrdered :: Connection -> IO [(Order, Int)]
ordersWithCostOrdered conn =
  withDatabaseDebug putStrLn conn $
      runSelectReturningList $ select $
      orderBy_ (\(order, total) -> desc_ total) $
      aggregate_ (\(order, lineItem, product) ->
                    (group_ order, sum_ (lineItem ^. lineItemQuantity * product ^. productPrice))) $
      do
        lineItem <- all_ (shoppingCartDb ^. shoppingCartLineItems)
        order    <- related_ (shoppingCartDb ^. shoppingCartOrders) (_lineItemInOrder lineItem)
        product  <- related_ (shoppingCartDb ^. shoppingCartProducts) (_lineItemForProduct lineItem)
        pure (order, lineItem, product)

allUsersAndTotals :: Connection -> IO [(User, Int)]
allUsersAndTotals conn =
  withDatabaseDebug putStrLn conn $
      runSelectReturningList $
      select $
      orderBy_ (\(user, total) -> desc_ total) $
      aggregate_ (\(user, lineItem, product) ->
                    (group_ user, sum_ (maybe_ 0 id (_lineItemQuantity lineItem) * maybe_ 0 id (product ^. productPrice)))) $
      do user     <- all_ (shoppingCartDb ^. shoppingCartUsers)
         order    <- leftJoin_ (all_ (shoppingCartDb ^. shoppingCartOrders))
                              (\order -> _orderForUser order `references_` user)
         lineItem <- leftJoin_ (all_ (shoppingCartDb ^. shoppingCartLineItems))
                              (\lineItem -> maybe_ (val_ False) (\order -> _lineItemInOrder lineItem `references_` order) order)
         product  <- leftJoin_ (all_ (shoppingCartDb ^. shoppingCartProducts))
                              (\product -> maybe_ (val_ False) (\lineItem -> _lineItemForProduct lineItem `references_` product) lineItem)
         pure (user, lineItem, product)

allUnshippedOrders :: Connection -> IO [Order]
allUnshippedOrders conn =
  withDatabaseDebug putStrLn conn $
    runSelectReturningList $
    select $
    filter_ (isNothing_ . _orderShippingInfo) $
    all_ (shoppingCartDb ^. shoppingCartOrders)

shippingInformationByUser :: Connection -> IO [(User, Int, Int)]
shippingInformationByUser conn =
  withDatabaseDebug putStrLn conn $
    runSelectReturningList $
    select $
    aggregate_ (\(user, order) ->
                   let ShippingInfoId shippingInfoId = _orderShippingInfo order
                   in ( group_ user
                      , as_ @Int $ count_ (as_ @(Maybe Int) (maybe_ (just_ 1) (\_ -> nothing_) shippingInfoId))
                      , as_ @Int $ count_ shippingInfoId ) ) $
    do user  <- all_ (shoppingCartDb ^. shoppingCartUsers)
       order <- leftJoin_ (all_ (shoppingCartDb ^. shoppingCartOrders)) (\order -> _orderForUser order `references_` user)
       pure (user, order)

shippingInformationByUserSubselect :: Connection -> IO [(User, Int, Int)]
shippingInformationByUserSubselect conn =
  withDatabaseDebug putStrLn conn $
    runSelectReturningList $
    select $
    do user <- all_ (shoppingCartDb ^. shoppingCartUsers)

       (userEmail, unshippedCount) <-
         aggregate_ (\(userEmail, order) -> (group_ userEmail, countAll_)) $
         do user  <- all_ (shoppingCartDb ^. shoppingCartUsers)
            order <- leftJoin_ (all_ (shoppingCartDb ^. shoppingCartOrders))
                               (\order -> _orderForUser order `references_` user &&. isNothing_ (_orderShippingInfo order))
            pure (pk user, order)

       guard_ (userEmail `references_` user)

       (userEmail, shippedCount) <-
         aggregate_ (\(userEmail, order) -> (group_ userEmail, countAll_)) $
         do user  <- all_ (shoppingCartDb ^. shoppingCartUsers)
            order <- leftJoin_ (all_ (shoppingCartDb ^. shoppingCartOrders))
                               (\order -> _orderForUser order `references_` user &&. isJust_ (_orderShippingInfo order))
            pure (pk user, order)
       guard_ (userEmail `references_` user)

       pure (user, unshippedCount, shippedCount)

shippingInformationByUserSubselectCombinator :: Connection -> IO [(User, Int, Int)]
shippingInformationByUserSubselectCombinator conn =
  withDatabaseDebug putStrLn conn $
    runSelectReturningList $
    select $
    do user <- all_ (shoppingCartDb ^. shoppingCartUsers)

       (userEmail, unshippedCount) <-
         subselect_ $
         aggregate_ (\(userEmail, order) -> (group_ userEmail, countAll_)) $
         do user  <- all_ (shoppingCartDb ^. shoppingCartUsers)
            order <- leftJoin_ (all_ (shoppingCartDb ^. shoppingCartOrders))
                               (\order -> _orderForUser order `references_` user &&. isNothing_ (_orderShippingInfo order))
            pure (pk user, order)

       guard_ (userEmail `references_` user)

       (userEmail, shippedCount) <-
         subselect_ $
         aggregate_ (\(userEmail, order) -> (group_ userEmail, countAll_)) $
         do user  <- all_ (shoppingCartDb ^. shoppingCartUsers)
            order <- leftJoin_ (all_ (shoppingCartDb ^. shoppingCartOrders))
                               (\order -> _orderForUser order `references_` user &&. isJust_ (_orderShippingInfo order))
            pure (pk user, order)
       guard_ (userEmail `references_` user)

       pure (user, unshippedCount, shippedCount)

bettyEmail :: Text
bettyEmail = "betty@example.com"

selectAddressForBetty :: Connection -> IO [Address]
selectAddressForBetty conn =
  withDatabaseDebug putStrLn conn $
    runSelectReturningList $ select $ do
      address <- all_ (shoppingCartDb ^. shoppingCartUserAddresses)
      guard_ (address ^. addressForUserId ==. val_ bettyEmail)
      return address

bettyId :: UserId
bettyId = UserId "betty@example.com"

selectAddressForBettyId :: Connection -> IO [Address]
selectAddressForBettyId conn =
  withDatabaseDebug putStrLn conn $
    runSelectReturningList $ select $ do
      address <- all_ (shoppingCartDb ^. shoppingCartUserAddresses)
      guard_ (_addressForUser address ==. val_ bettyId)
      return address

updatingUserWithSave :: Connection -> IO ()
updatingUserWithSave conn = do
  [james] <- withDatabaseDebug putStrLn conn $
             do
               runUpdate $
                 save (shoppingCartDb ^. shoppingCartUsers) (james {_userPassword = "52a516ca6df436828d9c0d26e31ef704" })

               runSelectReturningList $
                 B.lookup (shoppingCartDb ^. shoppingCartUsers) (UserId "james@example.com")

  putStrLn ("James's new password is " ++ show (james ^. userPassword))

updatingAddressesWithFinerGrainedControl :: Connection -> IO ()
updatingAddressesWithFinerGrainedControl conn = do
  addresses <- withDatabaseDebug putStrLn conn $
               do
                 runUpdate $
                    update (shoppingCartDb ^. shoppingCartUserAddresses)
                           (\address -> [ address ^. addressCity <-. val_ "Sugarville"
                                        , address ^. addressZip <-. "12345"])
                           (\address -> address ^. addressCity ==. val_ "Sugarland" &&.
                                        address ^. addressState ==. val_ "TX")
                 runSelectReturningList $ select $ all_ (shoppingCartDb ^. shoppingCartUserAddresses)

  mapM_ print addresses

sortUsersByFirstName :: Connection -> IO ()
sortUsersByFirstName conn =
  withDatabaseDebug putStrLn conn $ do
    users <- runSelectReturningList $ select sortUsersByFirstName
    mapM_ (liftIO . putStrLn . show) users
  where
    sortUsersByFirstName = orderBy_ (\u -> (asc_ (_userFirstName u), desc_ (_userLastName u))) allUsers

boundedUsers :: Connection -> IO ()
boundedUsers conn =
  withDatabaseDebug putStrLn conn $ do
    users <- runSelectReturningList $ select boundedQuery
    mapM_ (liftIO . putStrLn . show) users
  where
    boundedQuery = limit_ 1 $ offset_ 1 $ orderBy_ (asc_ . _userFirstName) $ allUsers

userCount :: Connection -> IO ()
userCount conn =
  withDatabaseDebug putStrLn conn $ do
    Just c <- runSelectReturningOne $ select userCount
    liftIO $ putStrLn ("We have " ++ show c ++ " users in the database")
  where
    userCount = aggregate_ (\u -> as_ @Int countAll_) allUsers

numberOfUsersByName :: Connection -> IO ()
numberOfUsersByName conn =
  withDatabaseDebug putStrLn conn $ do
    countedByName <- runSelectReturningList $ select numberOfUsersByName
    mapM_ (liftIO . putStrLn . show) countedByName
  where
    numberOfUsersByName = aggregate_ (\u -> (group_ (_userFirstName u), as_ @Int countAll_)) allUsers

main :: IO ()
main = do
  conn <- connectPostgreSQL "host=localhost dbname=shoppingcart3"
  insertUsers conn
  addresses@[jamesAddress1, bettyAddress1, bettyAddress2] <- insertAddresses conn
  products@[redBall, mathTextbook, introToHaskell, suitcase] <- insertProducts conn
  [bettyShippingInfo] <- insertShippingInfos conn
  orders@[jamesOrder1, bettyOrder1, jamesOrder2] <- insertOrders conn addresses bettyShippingInfo
  insertLineItems conn orders products
  mapM_ print =<< selectAllUsersAndOrdersLeftJoin conn
