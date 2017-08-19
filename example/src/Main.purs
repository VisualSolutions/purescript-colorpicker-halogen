module Main where

import Prelude

import Color (Color, rgb)
import ColorPicker.Halogen.ColorComponents as C
import ColorPicker.Halogen.Component as CPicker
import ColorPicker.Halogen.Layout as L
import Control.Monad.Aff.Class (class MonadAff)
import Control.Monad.Eff (Eff)
import Control.MonadZero (guard)
import Data.Array (reverse)
import Data.Either.Nested as Either
import Data.Functor.Coproduct.Nested as Coproduct
import Data.Map (Map, insert, lookup)
import Data.Maybe (Maybe(..), maybe')
import Data.Monoid (mempty)
import Halogen (ClassName(..))
import Halogen as H
import Halogen.Aff as HA
import Halogen.Component.ChildPath as CP
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.VDom.Driver (runUI)

main ∷ Eff (HA.HalogenEffects ()) Unit
main = HA.runHalogenAff do
  body ← HA.awaitBody
  runUI example unit body

data Query a = HandleMsg ColorIdx CPicker.Message a

type State = Map Int {current ∷ Color, next ∷ Color }
type ColorIdx = Int
type ChildQuery = Coproduct.Coproduct1 CPicker.Query
type Slot = Either.Either1 ColorIdx


cpColor ∷ CP.ChildPath CPicker.Query ChildQuery ColorIdx Slot
cpColor = CP.cp1


type HTML m = H.ParentHTML Query ChildQuery Slot m
type DSL m = H.ParentDSL State Query ChildQuery Slot Void m


example ∷ ∀ m r. MonadAff (CPicker.PickerEffects r) m => H.Component HH.HTML Query Unit Void m
example = H.parentComponent
    { initialState: const mempty
    , render
    , eval
    , receiver: const Nothing
    }

render ∷ ∀ m r. MonadAff (CPicker.PickerEffects r) m => State → HTML m
render state = HH.div_
  $ renderPicker 0 config0
  <> renderPicker 1 config1
  <> renderPicker 2 config2

  where
  renderPicker idx conf =
    [ HH.h1_ [ HH.text $ "Picker " <> show idx ]
    , HH.slot' cpColor idx CPicker.picker conf (HE.input $ HandleMsg idx)
    , HH.p_ [ HH.text case lookup idx state of
        Just ({current, next}) →
          "uncommited (current: " <> show current <>", next:" <> show next <> ")"
        Nothing → "no color"
      ]
    ]

eval ∷ ∀ m. Query ~> DSL m
eval (HandleMsg idx msg next) = do
  H.modify update
  pure next
  where
  update state = insert idx val state
    where
    val = case lookup idx state, msg of
      Just s, CPicker.NextChange nextVal → s{next = nextVal}
      _, CPicker.NextChange x → { next: x, current: x }
      _, CPicker.NotifyChange x →  {next: x, current: x}

config0 ∷ CPicker.Props
config0 = mkConf reverse
  (ClassName "ColorPicker--small")
  [ [ C.componentHue
    , C.componentSaturationHSL
    , C.componentLightness
    ]
  ]

config1 ∷ CPicker.Props
config1 = mkConf id
  (ClassName "ColorPicker--large")
  [ [ C.componentHue
    , C.componentSaturationHSV
    , C.componentValue
    , C.componentSaturationHSL
    , C.componentLightness
    ]
  , [ C.componentRed
    , C.componentGreen
    , C.componentBlue
    , C.componentHEX
    ]
  ]

config2 ∷ CPicker.Props
config2 = mkConf id
  (ClassName "ColorPicker--small")
  [ [ const componentRedORNoRed ]]

componentRedORNoRed ∷ C.ColorComponent
componentRedORNoRed = C.TextComponentSpec
  { fromString: \str → if str == "red" then Just (red) else Nothing
  , view: \{color, value, onBlur, onValueInput } -> pure $
      HH.label
        [ HP.classes inputClasses.root]
        [ HH.span [HP.classes inputClasses.label] [HH.text "🛑"]
        , HH.input
          [ HP.type_ HP.InputText
          , HP.classes
            $  inputClasses.elem
            <> (guard (C.isInvalid value) *> (inputClasses.elemInvalid))
          , HP.title "red or nored?"
          , HP.value $ maybe' (\_ -> toString color) _.value value
          , HP.placeholder "red"
          , HE.onValueInput $ onValueInput >>> Just
          , HE.onBlur $ onBlur >>> Just
          ]
        ]
  }
  where
  red = rgb 255 0 0
  toString =  \{color} → if color == red then "red" else "noRed"




mkConf
  ∷ (∀ a. Array a → Array a)
  → ClassName
  → Array (Array (C.InputProps C.Classes → C.ColorComponent))
  → CPicker.Props
mkConf reverse' root editGroups =
  { layout:
    L.Root [ ClassName "ColorPicker", root ] $ reverse'
      [ [ ClassName "ColorPicker-dragger" ] `L.Group`
          [ L.Component $ C.componentDragSV
              { root: [ ClassName "ColorPicker-field" ]
              , isLight: [ ClassName "IsLight" ]
              , isDark: [ ClassName "IsDark" ]
              , selector: [ ClassName "ColorPicker-fieldSelector"]
              }
          , L.Component $ C.componentDragHue
              { root: [ ClassName "ColorPicker-slider" ]
              , selector: [ ClassName "ColorPicker-sliderSelector"]
              }
          ]
      , [ ClassName "ColorPicker-aside" ] `L.Group`
          [ [ ClassName "ColorPicker-stage" ] `L.Group`
              [ L.Component $ C.componentPreview [ ClassName "ColorPicker-colorBlockCurrent" ]
              , L.Component $ C.componentHistory [ ClassName "ColorPicker-colorBlockOld" ]
              ]
          , L.Group [ ClassName "ColorPicker-editing" ] $
              editGroups <#> \editGroup →
                L.Group [ ClassName "ColorPicker-editingItem" ] $
                  editGroup <#> \mkItem -> L.Component $ mkItem inputClasses
          , [ ClassName "ColorPicker-actions" ] `L.Group`
              [ L.Component $ C.componentSet [ ClassName "ColorPicker-actionSet" ] ]
          ]
      ]
  }

inputClasses ∷ C.InputProps C.Classes
inputClasses =
  { root: [ClassName "ColorPicker-input"]
  , label: [ClassName "ColorPicker-inputLabel"]
  , elem: [ClassName "ColorPicker-inputElem"]
  , elemInvalid: [ClassName "ColorPicker-inputElem--invalid"]
  }
