module Contract.View
  ( contractDetailsCard
  , actionConfirmationCard
  ) where

import Prelude hiding (div)
import Contract.Lenses (_executionState, _mActiveUserParty, _metadata, _participants, _tab)
import Contract.State (currentStep, isContractClosed)
import Contract.Types (Action(..), State, Tab(..))
import Css (applyWhen, classNames)
import Css as Css
import Data.Array (foldr, intercalate)
import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.BigInteger (BigInteger, fromInt, fromString, toNumber)
import Data.Foldable (foldMap)
import Data.Formatter.Number (Formatter(..), format)
import Data.FunctorWithIndex (mapWithIndex)
import Data.Lens ((^.))
import Data.Map as Map
import Data.Maybe (Maybe(..), maybe, maybe')
import Data.Set (Set)
import Data.Set as Set
import Data.String as String
import Data.String.Extra (capitalize)
import Data.Tuple (Tuple(..), fst, uncurry)
import Data.Tuple.Nested ((/\))
import Halogen.HTML (HTML, a, button, div, div_, h1, h2, h3, input, p, span, span_, sup_, text)
import Halogen.HTML.Events.Extra (onClick_, onValueInput_)
import Halogen.HTML.Properties (InputType(..), enabled, href, placeholder, target, type_, value)
import Marlowe.Execution (ExecutionStep, NamedAction(..), _contract, _namedActions, _state, _steps, getActionParticipant)
import Marlowe.Extended (contractTypeName)
import Marlowe.Semantics (Bound(..), ChoiceId(..), Input(..), Party(..), SlotInterval, Token(..), TransactionInput(..), _accounts, getEncompassBound)
import Material.Icons (Icon(..), icon)

contractDetailsCard :: forall p. State -> HTML p Action
contractDetailsCard state =
  let
    metadata = state ^. _metadata

    pastStepsCards = mapWithIndex (renderPastStep state) (state ^. (_executionState <<< _steps))

    currentStepCard = [ renderCurrentStep state ]
  in
    div [ classNames [ "flex", "flex-col", "items-center", "my-5" ] ]
      [ h1 [ classNames [ "text-xl", "font-semibold" ] ] [ text metadata.contractName ]
      -- FIXME: in zeplin the contractType is defined with color #283346, we need to define
      --        the color palette with russ.
      , h2 [ classNames [ "mb-2", "text-xs", "uppercase" ] ] [ text $ contractTypeName metadata.contractType ]
      , div [ classNames [ "flex", "w-full", "overflow-x-scroll", "mr-5" ] ] (pastStepsCards <> currentStepCard)
      ]

actionConfirmationCard :: forall p. State -> NamedAction -> HTML p Action
actionConfirmationCard state namedAction =
  let
    stepNumber = currentStep state

    title = case namedAction of
      MakeDeposit _ _ _ _ -> "Deposit confirmation"
      MakeChoice _ _ _ -> "Choice confirmation"
      CloseContract -> "Close contract"
      _ -> "Fixme, this should not happen"

    cta = case namedAction of
      MakeDeposit _ _ _ _ -> "Deposit"
      MakeChoice _ _ _ -> "Choose"
      CloseContract -> "Pay to close"
      _ -> "Fixme, this should not happen"

    detailItem titleHtml amountHtml hasLeftItem =
      div [ classNames ([ "flex", "flex-col", "flex-1", "mb-2" ] <> applyWhen hasLeftItem [ "pl-2", "border-l", "border-gray" ]) ]
        [ span [ classNames [ "text-xs" ] ] titleHtml
        , span [ classNames [ "font-semibold" ] ] amountHtml
        ]

    transactionFeeItem = detailItem [ text "Transaction fee", sup_ [ text "*" ], text ":" ] [ text "₳ 0.00" ]

    actionAmountItems = case namedAction of
      MakeDeposit _ _ token amount ->
        [ detailItem [ text "Deposit amount:" ] [ text $ currency token amount ] false
        , transactionFeeItem true
        ]
      MakeChoice _ _ (Just option) ->
        [ detailItem [ text "You are choosing:" ] [ text $ "[ option " <> show option <> " ]" ] false
        , transactionFeeItem true
        ]
      _ -> [ transactionFeeItem false ]

    totalToPay = case namedAction of
      MakeDeposit _ _ token amount -> text $ currency token amount
      _ -> text $ currency (Token "" "") (fromInt 0)
  in
    div_
      [ div [ classNames [ "flex", "font-semibold", "justify-between", "bg-lightgray", "p-5" ] ]
          [ span_ [ text "Demo wallet balance:" ]
          -- FIXME: remove placeholder with actual value
          , span_ [ text "₳ 223,456.78" ]
          ]
      , div [ classNames [ "px-5", "pb-6", "pt-3", "md:pb-8" ] ]
          [ h2
              [ classNames [ "text-xl", "font-semibold" ] ]
              [ text $ "Step " <> show stepNumber ]
          , h3
              [ classNames [ "text-xs", "font-semibold" ] ]
              [ text title ]
          , div [ classNames [ "flex", "border-b", "border-gray", "mt-4" ] ]
              actionAmountItems
          , h3
              [ classNames [ "mt-4", "text-sm", "font-semibold" ] ]
              [ text "Confirm payment of:" ]
          , div
              [ classNames [ "mb-4", "text-purple", "font-semibold", "text-2xl" ] ]
              [ totalToPay ]
          , div [ classNames [ "flex", "justify-center" ] ]
              [ button
                  [ classNames $ Css.secondaryButton <> [ "mr-2", "flex-1" ]
                  , onClick_ CancelConfirmation
                  ]
                  [ text "Cancel" ]
              , button
                  [ classNames $ Css.primaryButton <> [ "flex-1" ]
                  , onClick_ $ ConfirmAction namedAction
                  ]
                  [ text cta ]
              ]
          , div [ classNames [ "bg-black", "text-white", "p-4", "mt-4", "rounded" ] ]
              [ h3 [ classNames [ "text-sm", "font-semibold" ] ] [ sup_ [ text "*" ], text "Transaction fees are estimates only:" ]
              , p [ classNames [ "pb-4", "border-b-half", "border-lightgray", "text-xs", "text-gray" ] ]
                  -- FIXME: review text with simon
                  [ text "In the demo all fees are free but in the live version the cost will depend on the status of the blockchain at the moment of the transaction" ]
              , div [ classNames [ "pt-4", "flex", "justify-between", "items-center" ] ]
                  [ a
                      -- FIXME: where should this link point to?
                      [ href "https://docs.cardano.org/en/latest/explore-cardano/cardano-fee-structure.html"
                      , classNames [ "font-bold" ]
                      , target "_blank"
                      ]
                      [ text "Read more in Docs" ]
                  , icon ArrowRight [ "text-2xl" ]
                  ]
              ]
          ]
      ]

renderContractCard :: forall p. State -> Array (HTML p Action) -> HTML p Action
renderContractCard state cardBody =
  let
    currentTab = state ^. _tab

    -- FIXME: in zepplin the font size is 6px (I think the scale is wrong), but proportionally is half of
    --        of the size of the Contract Title. I've set it a little bit bigger as it looked weird. Check with
    --        russ.
    tabSelector isActive =
      [ "flex-grow", "text-center", "py-2", "trapesodial-card-selector", "text-sm", "font-semibold" ]
        <> case isActive of
            true -> [ "active" ]
            false -> []
  in
    div [ classNames [ "rounded", "shadow-current-step", "overflow-hidden", "flex-grow", "ml-5", "max-w-contract-card", "min-w-contract-card" ] ]
      [ div [ classNames [ "flex", "overflow-hidden" ] ]
          [ a
              [ classNames (tabSelector $ currentTab == Tasks)
              , onClick_ $ SelectTab Tasks
              ]
              [ span_ $ [ text "Tasks" ] ]
          , a
              [ classNames (tabSelector $ currentTab == Balances)
              , onClick_ $ SelectTab Balances
              ]
              [ span_ $ [ text "Balances" ] ]
          ]
      , div [ classNames [ "max-h-contract-card", "bg-white" ] ] cardBody
      ]

statusIndicator :: forall p a. Maybe Icon -> String -> Array String -> HTML p a
statusIndicator mIcon status extraClasses =
  div
    [ classNames $ [ "flex-grow", "rounded-lg", "h-10", "flex", "items-center" ] <> extraClasses ]
    $ Array.catMaybes
        [ mIcon <#> \anIcon -> icon anIcon [ "pl-3" ]
        , Just $ span [ classNames [ "text-xs", "flex-grow", "text-center", "font-semibold" ] ] [ text status ]
        ]

renderPastStep :: forall p. State -> Int -> ExecutionStep -> HTML p Action
renderPastStep state stepNumber executionState =
  let
    -- FIXME: We need to make the tab independent.
    currentTab = state ^. _tab

    { timedOut } = executionState
  in
    renderContractCard state
      [ div [ classNames [ "py-2.5", "px-4", "flex", "items-center", "border-b", "border-lightgray" ] ]
          [ span
              [ classNames [ "text-xl", "font-semibold", "flex-grow" ] ]
              [ text $ "Step " <> show (stepNumber + 1) ]
          , if timedOut then
              -- FIXME: The red used here corresponds to #de4c51, which is being used by border-red invalid inputs
              --        but the zeplin had #e04b4c for this indicator. Check if it's fine or create a new red type
              statusIndicator (Just Timer) "Timed out" [ "bg-red", "text-white" ]
            else
              statusIndicator (Just Done) "Completed" [ "bg-green", "text-white" ]
          ]
      , div [ classNames [ "h-contract-card", "overflow-y-scroll", "px-4" ] ]
          [ case currentTab /\ timedOut of
              Tasks /\ false -> renderPastActions state executionState
              Tasks /\ true -> renderTimeout (stepNumber + 1)
              Balances /\ _ -> renderBalances state
          ]
      ]

type InputsByParty
  = { inputs :: Array Input, interval :: SlotInterval, party :: Party }

-- Normally we would expect that a TransactionInput has either no inputs or a single one
-- but the types allows for them to be a list of different inputs, possibly made by different
-- parties. If there are multiple inputs we group them by participant.
groupTransactionInputByParticipant :: TransactionInput -> Array InputsByParty
groupTransactionInputByParticipant (TransactionInput { inputs, interval }) =
  Array.fromFoldable inputs
    # Array.mapMaybe
        ( \input -> getParty input <#> (\party -> { inputs: [ input ], party })
        )
    # Array.groupBy sameParty
    # map mergeInputsFromSameParty
  where
  sameParty a b = a.party == b.party

  mergeInputsFromSameParty ::
    NonEmptyArray { inputs :: Array Input, party :: Party } ->
    InputsByParty
  mergeInputsFromSameParty nea =
    foldr
      (\elem accu -> accu { inputs = elem.inputs <> accu.inputs })
      (NEA.head nea # \{ party } -> { inputs: [], party, interval })
      nea

renderPastActions :: forall p a. State -> ExecutionStep -> HTML p a
renderPastActions state executionState =
  let
    actionsByParticipant = groupTransactionInputByParticipant executionState.txInput
  in
    div_
      $ if Array.length actionsByParticipant == 0 then
          -- TODO: See if we can reach this state and what text describes it better.
          [ text "An empty transaction was made to advance this step" ]
        else
          renderPartyPastActions state <$> actionsByParticipant

renderPartyPastActions :: forall p a. State -> InputsByParty -> HTML p a
renderPartyPastActions state { inputs, interval, party } =
  let
    participantName = participantWithNickname state party

    isActiveParticipant = (state ^. _mActiveUserParty) == Just party

    fromDescription =
      if isActiveParticipant then
        "You"
      else case party of
        PK publicKey -> "Account " <> publicKey
        Role roleName -> capitalize roleName

    -- FIXME: Take this from interval
    intervalDescrition = "on 10/03/2021 between 17:30 and 17:35"

    renderPastAction = case _ of
      IDeposit intoAccountOf by token value ->
        let
          toDescription =
            if (state ^. _mActiveUserParty) == Just intoAccountOf then
              "your"
            else
              if by == intoAccountOf then
                "their"
              else case intoAccountOf of
                PK publicKey -> publicKey <> " public key"
                Role roleName -> roleName <> "'s"
        in
          div [] [ text $ fromDescription <> " made a deposit of " <> currency token value <> " into " <> toDescription <> " account " <> intervalDescrition ]
      IChoice (ChoiceId choiceIdKey _) chosenNum -> div [] [ text $ fromDescription <> " chose " <> show chosenNum <> " for " <> show choiceIdKey <> " " <> intervalDescrition ]
      _ -> div_ []
  in
    div [ classNames [ "mt-4" ] ]
      ( [ renderParty state party ] <> map renderPastAction inputs
      )

renderTimeout :: forall p a. Int -> HTML p a
renderTimeout stepNumber =
  div [ classNames [ "flex", "flex-col", "items-center", "h-full" ] ]
    -- NOTE: we use pt-28 instead of making the parent justify-center because in the design it's not actually
    --       centered and it has more space above than below.
    [ icon Timer [ "pb-2", "pt-28", "text-red", "text-big-icon" ]
    -- FIXME: Need to pass a Slot and convert it to the appropiate format
    , span [ classNames [ "font-semibold", "text-center", "text-sm" ] ]
        [ text $ "Step " <> show stepNumber <> " timed out on 03/10/2021 at 17:30" ]
    ]

renderCurrentStep :: forall p. State -> HTML p Action
renderCurrentStep state =
  let
    stepNumber = currentStep state

    currentTab = state ^. _tab

    contractIsClosed = isContractClosed state
  in
    renderContractCard state
      [ div [ classNames [ "py-2.5", "px-4", "flex", "items-center", "border-b", "border-lightgray" ] ]
          [ span
              [ classNames [ "text-xl", "font-semibold", "flex-grow" ] ]
              [ text $ "Step " <> show stepNumber ]
          , if contractIsClosed then
              -- FIXME: Check with russ. The original status indicator for contract closed
              --        did not have an icon, but all other status indicator has. Check if
              --        this is fine or if we should use a Maybe icon.
              statusIndicator Nothing "Contract closed" [ "bg-lightgray" ]
            else
              statusIndicator (Just Timer) "1hr 2mins left" [ "bg-lightgray" ]
          ]
      , div [ classNames [ "h-contract-card", "overflow-y-scroll", "px-4" ] ]
          [ case currentTab /\ contractIsClosed of
              Tasks /\ false -> renderTasks state
              Tasks /\ true -> renderContractClose
              Balances /\ _ -> renderBalances state
          ]
      ]

renderContractClose :: forall p a. HTML p a
renderContractClose =
  div [ classNames [ "flex", "flex-col", "items-center", "h-full" ] ]
    -- NOTE: we use pt-28 instead of making the parent justify-center because in the design it's not actually
    --       centered and it has more space above than below.
    [ icon DoneWithCircle [ "pb-2", "pt-28", "text-green", "text-big-icon" ]
    -- FIXME: Need to pass a Slot and convert it to the appropiate format
    , div
        [ classNames [ "text-center", "text-sm" ] ]
        [ div [ classNames [ "font-semibold" ] ]
            [ text "This contract is now closed" ]
        , div_ [ text "There are no tasks to complete" ]
        ]
    ]

-- This helper function expands actions that can be taken by anybody,
-- then groups by participant and sorts it so that the owner starts first and the rest go
-- in alphabetical order
expandAndGroupByRole ::
  Maybe Party ->
  Set Party ->
  Array NamedAction ->
  Array (Tuple Party (Array NamedAction))
expandAndGroupByRole mActiveUserParty allParticipants actions =
  expandedActions
    # Array.sortBy currentPartyFirst
    # Array.groupBy sameParty
    # map extractGroupedParty
  where
  -- If an action has a participant, just use that, if it doesn't expand it to all
  -- participants
  expandedActions :: Array (Tuple Party NamedAction)
  expandedActions =
    actions
      # foldMap \action -> case getActionParticipant action of
          Just participant -> [ participant /\ action ]
          Nothing -> Set.toUnfoldable allParticipants <#> \participant -> participant /\ action

  currentPartyFirst (Tuple party1 _) (Tuple party2 _)
    | Just party1 == mActiveUserParty = LT
    | Just party2 == mActiveUserParty = GT
    | otherwise = compare party1 party2

  sameParty a b = fst a == fst b

  extractGroupedParty :: NonEmptyArray (Tuple Party NamedAction) -> Tuple Party (Array NamedAction)
  extractGroupedParty group = case NEA.unzip group of
    tokens /\ actions' -> NEA.head tokens /\ NEA.toArray actions'

renderTasks :: forall p. State -> HTML p Action
renderTasks state =
  let
    executionState = state ^. _executionState

    actions = executionState ^. _namedActions

    expandedActions =
      expandAndGroupByRole
        (state ^. _mActiveUserParty)
        (Map.keys $ state ^. _participants)
        actions

    contract = executionState ^. _contract
  in
    div [ classNames [ "pb-4" ] ] $ expandedActions <#> uncurry (renderPartyTasks state)

participantWithNickname :: State -> Party -> String
participantWithNickname state party =
  let
    mNickname :: Maybe String
    mNickname = join $ Map.lookup party (state ^. _participants)
  in
    capitalize case party /\ mNickname of
      -- TODO: For the demo we wont have PK, but eventually we probably want to limit the amount of characters
      PK publicKey /\ _ -> publicKey
      Role roleName /\ Just nickname -> roleName <> " (" <> nickname <> ")"
      Role roleName /\ Nothing -> roleName

-- TODO: In zeplin all participants have a different color. We need to decide how are we going to assing
--       colors to users. For now they all have purple
renderParty :: forall p a. State -> Party -> HTML p a
renderParty state party =
  let
    participantName = participantWithNickname state party
  in
    -- FIXME: mb-2 should not belong here
    div [ classNames [ "text-xs", "flex", "mb-2" ] ]
      [ div [ classNames [ "bg-gradient-to-r", "from-purple", "to-lightpurple", "text-white", "rounded-full", "w-5", "h-5", "text-center", "mr-1" ] ] [ text $ String.take 1 participantName ]
      , div [ classNames [ "font-semibold" ] ] [ text participantName ]
      ]

renderPartyTasks :: forall p. State -> Party -> Array NamedAction -> HTML p Action
renderPartyTasks state party actions =
  let
    actionsSeparatedByOr =
      intercalate
        [ div [ classNames [ "font-semibold", "text-center", "my-2", "text-xs" ] ] [ text "OR" ]
        ]
        (Array.singleton <<< renderAction state party <$> actions)
  in
    div [ classNames [ "mt-3" ] ]
      ([ renderParty state party ] <> actionsSeparatedByOr)

-- FIXME: This was added to allow anybody being able to do any actions for debug purposes...
--        Remove once the PAB is connected
debugMode :: Boolean
debugMode = true

-- The Party parameter represents who is taking the action
renderAction :: forall p. State -> Party -> NamedAction -> HTML p Action
renderAction state party namedAction@(MakeDeposit intoAccountOf by token value) =
  let
    isActiveParticipant = (state ^. _mActiveUserParty) == Just party

    fromDescription =
      if isActiveParticipant then
        "You make"
      else case party of
        PK publicKey -> "Account " <> publicKey <> " makes"
        Role roleName -> capitalize roleName <> " makes"

    toDescription =
      if (state ^. _mActiveUserParty) == Just intoAccountOf then
        "your"
      else
        if by == intoAccountOf then
          "their"
        else case intoAccountOf of
          PK publicKey -> publicKey <> " public key"
          Role roleName -> roleName <> "'s"

    description = fromDescription <> " a deposit into " <> toDescription <> " account"
  in
    div_
      [ shortDescription isActiveParticipant description
      , button
          -- FIXME: adapt to use button classes from Css module
          [ classNames $ [ "flex", "justify-between", "px-6", "font-bold", "w-full", "py-4", "mt-2", "rounded-lg", "shadow" ]
              <> if isActiveParticipant || debugMode then
                  [ "bg-gradient-to-r", "from-purple", "to-lightpurple", "text-white" ]
                else
                  [ "bg-gray", "text-black", "opacity-50", "cursor-default" ]
          , enabled $ isActiveParticipant || debugMode
          , onClick_ $ AskConfirmation namedAction
          ]
          [ span_ [ text "Deposit:" ]
          , span_ [ text $ currency token value ]
          ]
      ]

renderAction state party namedAction@(MakeChoice choiceId bounds mChosenNum) =
  let
    isActiveParticipant = (state ^. _mActiveUserParty) == Just party

    metadata = state ^. _metadata

    -- NOTE': We could eventually add an heuristic that if the difference between min and max is less
    --        than 10 elements, we could show a `select` instead of a input[number] and if the min==max
    --        we use a button that says "Choose `min`"
    Bound minBound maxBound = getEncompassBound bounds

    ChoiceId choiceIdKey _ = choiceId

    choiceDescription = case Map.lookup choiceIdKey metadata.choiceDescriptions of
      Nothing -> div_ []
      Just description -> shortDescription isActiveParticipant description

    isValid = maybe false (between minBound maxBound) mChosenNum
  in
    div_
      [ choiceDescription
      , div
          [ classNames [ "flex", "w-full", "shadow", "rounded-lg", "mt-2", "overflow-hidden", "focus-within:ring-1", "ring-black" ]
          ]
          [ input
              [ classNames [ "border-0", "py-4", "pl-4", "pr-1", "flex-grow", "focus:ring-0" ]
              , type_ InputNumber
              , enabled $ isActiveParticipant || debugMode
              , maybe'
                  (\_ -> placeholder $ "Choose between " <> show minBound <> " and " <> show maxBound)
                  (value <<< show)
                  mChosenNum
              , onValueInput_ $ ChangeChoice choiceId <<< fromString
              ]
          , button
              [ classNames
                  ( [ "px-5", "font-bold" ]
                      <> if isValid then
                          [ "bg-gradient-to-b", "from-purple", "to-lightpurple", "text-white" ]
                        else
                          [ "bg-gray", "text-black", "opacity-50", "cursor-default" ]
                  )
              , onClick_ $ AskConfirmation namedAction
              , enabled $ isValid && isActiveParticipant
              ]
              [ text "..." ]
          ]
      ]

renderAction _ _ (MakeNotify _) = div [] [ text "FIXME: awaiting observation?" ]

renderAction _ _ (Evaluate _) = div [] [ text "FIXME: what should we put here? Evaluate" ]

renderAction state party CloseContract =
  let
    isActiveParticipant = (state ^. _mActiveUserParty) == Just party
  in
    div_
      -- FIXME: revisit the text
      [ shortDescription isActiveParticipant "The contract is still open and needs to be manually closed by any participant for the remainder of the balances to be distributed (charges may apply)"
      , button
          -- FIXME: adapt to use button classes from Css module
          [ classNames $ [ "font-bold", "w-full", "py-4", "mt-2", "rounded-lg", "shadow" ]
              <> if isActiveParticipant then
                  [ "bg-gradient-to-r", "from-purple", "to-lightpurple", "text-white" ]
                else
                  [ "bg-gray", "text-black", "opacity-50", "cursor-default" ]
          , enabled isActiveParticipant
          , onClick_ $ AskConfirmation CloseContract
          ]
          [ text "Close contract" ]
      ]

currencyFormatter :: Formatter
currencyFormatter =
  Formatter
    { sign: false
    , before: 0
    , comma: true
    , after: 0
    , abbreviations: false
    }

formatBigInteger :: BigInteger -> String
formatBigInteger = format currencyFormatter <<< toNumber

currency :: Token -> BigInteger -> String
-- FIXME: value should be interpreted as lovelaces instead of ADA and we should
--        display just the necesary amounts of digits
currency (Token "" "") value = "₳ " <> formatBigInteger value

currency (Token "" "dollar") value = "$ " <> formatBigInteger value

currency (Token _ name) value = formatBigInteger value <> " " <> name

renderBalances :: forall p a. State -> HTML p a
renderBalances state =
  let
    accounts :: Array (Tuple (Tuple Party Token) BigInteger)
    accounts = Map.toUnfoldable $ state ^. (_executionState <<< _state <<< _accounts)

    -- FIXME: What should we show if a participant doesn't have balance yet?
    -- FIXME: We fake the accounts for development until we fix the semantics
    accounts' =
      [ (Role "alice" /\ Token "" "") /\ (fromInt 2500)
      , (Role "bob" /\ Token "" "") /\ (fromInt 10)
      ]
  in
    div [ classNames [ "text-xs" ] ]
      ( append
          [ div [ classNames [ "font-semibold", "py-3" ] ] [ text "Balance of accounts when the step was initiated." ]
          ]
          ( accounts'
              <#> ( \((party /\ token) /\ amount) ->
                    div [ classNames [ "flex", "justify-between", "py-3", "border-t" ] ]
                      [ span_ [ text $ participantWithNickname state party ]
                      , span [ classNames [ "font-semibold" ] ] [ text $ currency token amount ]
                      ]
                )
          )
      )

shortDescription :: forall p a. Boolean -> String -> HTML p a
shortDescription isActiveParticipant description =
  div [ classNames ([ "text-xs" ] <> applyWhen (not isActiveParticipant) [ "opacity-50" ]) ]
    [ span [ classNames [ "font-semibold" ] ] [ text "Short description: " ]
    , span_ [ text description ]
    ]

getParty :: Input -> Maybe Party
getParty (IDeposit _ p _ _) = Just p

getParty (IChoice (ChoiceId _ p) _) = Just p

getParty _ = Nothing
