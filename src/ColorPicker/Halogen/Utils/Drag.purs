module ColorPicker.Halogen.Utils.Drag
  ( dragEventSource
  , DragData
  , CursorEvent
  , DragEvent(..)
  , DragEffects
  , Position
  , cursorEventToPosition
  , cursorEventToTarget
  , mkDragData
  ) where

import Prelude

import Control.Alt ((<|>))
import Control.Monad.Aff.AVar (AVAR)
import Control.Monad.Aff.Class (class MonadAff)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Ref (REF, newRef, readRef, writeRef)
import Control.Monad.Except (runExcept)
import DOM (DOM)
import DOM.Classy.Event (target)
import DOM.Classy.HTMLElement (getBoundingClientRect)
import DOM.Classy.Node (fromNode)
import DOM.Event.EventTarget (EventListener, eventListener, addEventListener, removeEventListener)
import DOM.Event.MouseEvent as MouseE
import DOM.Event.TouchEvent as TouchE
import DOM.Event.Types (Event, EventType)
import DOM.HTML (window)
import DOM.HTML.Event.EventTypes (mousemove, mouseup, touchend, touchmove)
import DOM.HTML.Types (HTMLElement, windowToEventTarget)
import DOM.HTML.Window (scrollX, scrollY)
import DOM.Node.Types (Node)
import Data.Either (Either(..), either, hush)
import Data.Foldable (traverse_)
import Data.Int (toNumber)
import Data.Maybe (Maybe(..), fromMaybe)
import Debug.Trace (spy)
import Halogen.Query.EventSource as ES


type DragData =
  { page ∷ Position
  , progress ∷ Position
  , pointer ∷ Position
  , delta ∷ Position
  , offset ∷ Position
  }

type CursorEvent = Either MouseE.MouseEvent TouchE.TouchEvent

data DragEvent
  = Move CursorEvent DragData
  | Done CursorEvent

type DragEffects eff =
  ( dom ∷ DOM
  , ref ∷ REF
  , avar ∷ AVAR
  | eff
  )

type Position =
  { x ∷ Number
  , y ∷ Number
  }

dragEventSource
  ∷ ∀ f m eff
  . MonadAff (DragEffects eff) m
  ⇒ CursorEvent
  → (DragEvent → Maybe (f ES.SubscribeStatus))
  → ES.EventSource f m
dragEventSource cursorEvent = ES.eventSource' \emit → do
  let node = cursorEventToTarget cursorEvent
  let initPos = cursorEventToPosition cursorEvent
  posRef ← newRef initPos
  let
    removeListeners ∷ Eff (DragEffects eff) Unit
    removeListeners = do
      win ← windowToEventTarget <$> window
      removeEventListener (cursorMoveFromEvent cursorEvent) cursorMove false win
      removeEventListener (cursorUpFromEvent cursorEvent) cursorUp false win

    cursorMove ∷ EventListener (DragEffects eff)
    cursorMove = eventListener $ onCursorEvent \event → do
      prevPos ← readRef posRef
      dragData <- mkDragData {prev:prevPos, init: initPos} event node
      writeRef posRef dragData.page
      emit $ Move event dragData

    cursorUp ∷ EventListener (DragEffects eff)
    cursorUp = eventListener $ onCursorEvent \event → do
      removeListeners
      emit $ Done event

  win ← windowToEventTarget <$> window
  addEventListener (cursorMoveFromEvent cursorEvent) cursorMove false win
  addEventListener (cursorUpFromEvent cursorEvent) cursorUp false win
  pure removeListeners

cursorUpFromEvent ∷ CursorEvent → EventType
cursorUpFromEvent (Left _) = mouseup
cursorUpFromEvent (Right _) = touchend

cursorMoveFromEvent ∷ CursorEvent → EventType
cursorMoveFromEvent (Left _) = mousemove
cursorMoveFromEvent (Right _) = touchmove

onCursorEvent ∷ ∀ m. Applicative m => (CursorEvent → m Unit) → (Event → m Unit)
onCursorEvent f event = traverse_ f $
  map Left asMouseEvent <|> map Right asTouchEvent
  where
  asMouseEvent = hush $ runExcept $ MouseE.eventToMouseEvent event
  asTouchEvent = hush $ runExcept $ TouchE.eventToTouchEvent event

cursorEventToTarget ∷ CursorEvent → Node
cursorEventToTarget = either target target

cursorEventToPosition ∷ CursorEvent → Position
cursorEventToPosition (Left e) =
  { x: toNumber $ MouseE.pageX e
  , y: toNumber $ MouseE.pageY e
  }
cursorEventToPosition (Right e) =
  case TouchE.item 0 $ TouchE.touches e of
    Nothing → positionZero
    Just t →
      { x: toNumber $ TouchE.pageX t
      , y: toNumber $ TouchE.pageY t
      }

type DomRect =
  { left ∷ Number
  , right ∷ Number
  , top ∷ Number
  , bottom ∷ Number
  , width ∷ Number
  , height ∷ Number
  }

scrollPosition :: ∀ r. Eff (dom ∷ DOM | r) Position
scrollPosition = do
  w ← window
  x ← toNumber <$> scrollX w
  y ← toNumber <$> scrollY w
  pure {x, y}

absoluteDomRect
  ∷ DomRect
  → Position
  → DomRect
absoluteDomRect rect scrollPos = rect
  { left = rect.left + scrollPos.x
  , right = rect.right + scrollPos.x
  , top = rect.top + scrollPos.y
  , bottom = rect.bottom + scrollPos.y
  }

nodeBoundingClientRect
  ∷ ∀ r
  . Node
  → Eff (dom ∷ DOM | r) DomRect
nodeBoundingClientRect node = map fixRect $ fromMaybe
  (pure {left: 0.0, right: 0.0, top: 0.0, bottom: 0.0, width: 0.0, height: 0.0})
  (getBoundingClientRect <$>elem)
  where
  elem ∷ Maybe HTMLElement
  elem = fromNode $ node
  fixRect {left, right, top, bottom, width, height} =
    {left, right, top, bottom, width, height}

clapInRect ∷ Position → DomRect → Position
clapInRect { x, y } { left, right, top, bottom } =
  { x: clamp left right x
  , y: clamp top bottom y
  }

positionInRect ∷ Position → DomRect → Position
positionInRect { x, y } { left, right, top, bottom } =
  { x: x - left
  , y: y - top
  }

progressInRect ∷ Position → DomRect → Position
progressInRect { x, y } { left, width, top, height } =
  { x: x / width * 100.0
  , y: y / height * 100.0
  }

mkDragData
  ∷ ∀ r
  . { prev ∷ Position , init ∷ Position }
  → CursorEvent
  → Node
  → Eff ( dom ∷ DOM | r ) DragData
mkDragData pos event node = do
  rect ← absoluteDomRect <$> (nodeBoundingClientRect node) <*> scrollPosition
  let pagePos = cursorEventToPosition event `clapInRect` rect
  let pointer = pagePos `positionInRect` rect
  let progress = pointer `progressInRect` rect
  pure
    { page: pagePos
    , pointer -- in rect
    , progress
    , delta: { x: pagePos.x - pos.prev.x, y: pagePos.y - pos.prev.y }
    , offset: { x: pagePos.x - pos.init.x, y : pagePos.y - pos.init.y }
    }

positionZero ∷ Position
positionZero = { x: 0.0, y: 0.0 }
