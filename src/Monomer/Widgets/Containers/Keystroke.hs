{-|
Module      : Monomer.Widgets.Containers.Keystroke
Copyright   : (c) 2018 Francisco Vallarino
License     : BSD-3-Clause (see the LICENSE file)
Maintainer  : fjvallarino@gmail.com
Stability   : experimental
Portability : non-portable

Container which generates user provided events when combinations of keys occur.
Using these event makes sense at the application or Composite level. If you are
implementing a widget from scratch, keyboard events are directly available.

The shortcut definitions are provided as a list of tuples of 'Text', containing
the key combination and associated event. The widget handles unordered
combinations of multiple keys at the same time, but does not support ordered
sequences (pressing "a", releasing, then "b" and "c"). The available keys are:

- Mod keys: A, Alt, C, Ctrl, Cmd, O, Option, S, Shift
- Action keys: Caps, Delete, Enter, Esc, Return, Space, Tab
- Arrows: Up, Down, Left, Right
- Function keys: F1-F12
- Lowercase letters (uppercase keys are reserved for mod and action keys)
- Numbers

These can be combined, for example:

- Copy: "Ctrl-c" or "C-c"
- App config: "Ctrl-Shift-p" or "C-S-p"
-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE Strict #-}

module Monomer.Widgets.Containers.Keystroke (
  -- * Configuration
  KeystrokeCfg,
  -- * Constructors
  keystroke,
  keystroke_
) where

import Control.Applicative ((<|>))
import Control.Lens ((&), (^.), (^..), (.~), (%~), _1, at, folded)
import Control.Lens.TH (abbreviatedFields, makeLensesWith)
import Data.Bifunctor (first)
import Data.Char (chr, isAscii, isPrint, ord)
import Data.Default
import Data.List (foldl')
import Data.Set (Set)
import Data.Text (Text)

import qualified Data.Map as M
import qualified Data.Sequence as Seq
import qualified Data.Set as Set
import qualified Data.Text as T

import Monomer.Widgets.Container

import qualified Monomer.Lens as L

{-|
Configuration options for keystroke:

- 'ignoreChildrenEvts': If True, when a shortcut is detected, the KeyAction
  event will not be passed down to children.
-}
newtype KeystrokeCfg = KeystrokeCfg {
  _kscIgnoreChildren :: Maybe Bool
}

instance Default KeystrokeCfg where
  def = KeystrokeCfg {
    _kscIgnoreChildren = Nothing
  }

instance Semigroup KeystrokeCfg where
  (<>) t1 t2 = KeystrokeCfg {
    _kscIgnoreChildren = _kscIgnoreChildren t2 <|> _kscIgnoreChildren t1
  }

instance Monoid KeystrokeCfg where
  mempty = def

instance CmbIgnoreChildrenEvts KeystrokeCfg where
  ignoreChildrenEvts_ ignore = def {
    _kscIgnoreChildren = Just ignore
  }

data KeyStroke = KeyStroke {
  _kstKsText :: Text,
  _kstKsC :: Bool,
  _kstKsCtrl :: Bool,
  _kstKsCmd :: Bool,
  _kstKsAlt :: Bool,
  _kstKsShift :: Bool,
  _kstKsKeys :: Set KeyCode
} deriving (Eq, Show)

instance Default KeyStroke where
  def = KeyStroke {
    _kstKsText = "",
    _kstKsC = False,
    _kstKsCtrl = False,
    _kstKsCmd = False,
    _kstKsAlt = False,
    _kstKsShift = False,
    _kstKsKeys = Set.empty
  }

newtype KeyStrokeState e = KeyStrokeState {
  _kssLatest :: [(KeyStroke, e)]
} deriving (Eq, Show)

makeLensesWith abbreviatedFields ''KeyStroke
makeLensesWith abbreviatedFields ''KeyStrokeState

-- | Creates a keystroke container with a single node as child.
keystroke :: WidgetEvent e => [(Text, e)] -> WidgetNode s e -> WidgetNode s e
keystroke bindings managed = keystroke_ bindings def managed

-- | Creates a keystroke container with a single node as child. Accepts config,
keystroke_
  :: WidgetEvent e
  => [(Text, e)]
  -> [KeystrokeCfg]
  -> WidgetNode s e
  -> WidgetNode s e
keystroke_ bindings configs managed = makeNode widget managed where
  config = mconcat configs
  newBindings = fmap (first textToStroke) bindings
  state = KeyStrokeState []
  widget = makeKeystroke newBindings config state

makeNode :: Widget s e -> WidgetNode s e -> WidgetNode s e
makeNode widget managedWidget = defaultWidgetNode "keystroke" widget
  & L.info . L.focusable .~ False
  & L.children .~ Seq.singleton managedWidget

makeKeystroke
  :: WidgetEvent e
  => [(KeyStroke, e)]
  -> KeystrokeCfg
  -> KeyStrokeState e
  -> Widget s e
makeKeystroke bindings config state = widget where
  widget = createContainer state def {
    containerMerge = merge,
    containerHandleEvent = handleEvent
  }

  merge wenv node oldNode oldState = resultNode newNode where
    newNode = node
      & L.widget .~ makeKeystroke bindings config oldState

  handleEvent wenv node target evt = case evt of
    KeyAction mod code KeyPressed -> Just result where
      newWenv = wenv & L.inputStatus %~ removeMods
      matches = filter (keyStrokeActive newWenv code . fst) bindings
      newState = KeyStrokeState matches
      newNode = node
        & L.widget .~ makeKeystroke bindings config newState
      evts = snd <$> matches
      reqs
        | ignoreChildren && not (null evts) = [IgnoreChildrenEvents]
        | otherwise = []
      result = resultReqsEvts newNode reqs evts
    TextInput t
      | ignoreChildren && ignorePrevious t -> Just result where
        previousMatch t = t `elem` _kssLatest state ^.. folded . _1 . ksText
        ignorePrevious t = isTextValidCode t && previousMatch t
        newState = KeyStrokeState []
        newNode = node
          & L.widget .~ makeKeystroke bindings config newState
        result = resultReqs newNode [IgnoreChildrenEvents]
    _ -> Nothing
    where
      ignoreChildren = Just True == _kscIgnoreChildren config

keyStrokeActive :: WidgetEnv s e -> KeyCode -> KeyStroke -> Bool
keyStrokeActive wenv code ks = currValid && allPressed && validMods where
  status = wenv ^. L.inputStatus
  keyMod = status ^. L.keyMod
  pressedKeys = M.filter (== KeyPressed) (status ^. L.keys)

  currValid = code `elem` (ks ^. ksKeys) || code `elem` modKeys
  allPressed = M.keysSet pressedKeys == ks ^. ksKeys

  ctrlPressed = isCtrlPressed keyMod
  cmdPressed = isMacOS wenv && isGUIPressed keyMod

  validC = not (ks ^. ksC) || ks ^. ksC == (ctrlPressed || cmdPressed)
  validCtrl = ks ^. ksCtrl == ctrlPressed || ctrlPressed && validC
  validCmd = ks ^. ksCmd == cmdPressed || cmdPressed && validC
  validShift = ks ^. ksShift == isShiftPressed keyMod
  validAlt = ks ^. ksAlt == isAltPressed keyMod

  validMods = (validC && validCtrl && validCmd) && validShift && validAlt

textToStroke :: Text -> KeyStroke
textToStroke text = ks where
  parts = T.split (=='-') text
  ks = foldl' partToStroke def parts
    & ksText .~ text

partToStroke :: KeyStroke -> Text -> KeyStroke
partToStroke ks "A" = ks & ksAlt .~ True
partToStroke ks "Alt" = ks & ksAlt .~ True
partToStroke ks "C" = ks & ksC .~ True
partToStroke ks "Ctrl" = ks & ksCtrl .~ True
partToStroke ks "Cmd" = ks & ksCmd .~ True
partToStroke ks "O" = ks & ksAlt .~ True
partToStroke ks "Option" = ks & ksAlt .~ True
partToStroke ks "S" = ks & ksShift .~ True
partToStroke ks "Shift" = ks & ksShift .~ True
-- Main keys
partToStroke ks "Caps" = ks & ksKeys %~ Set.insert keyCapsLock
partToStroke ks "Delete" = ks & ksKeys %~ Set.insert keyDelete
partToStroke ks "Enter" = ks & ksKeys %~ Set.insert keyReturn
partToStroke ks "Esc" = ks & ksKeys %~ Set.insert keyEscape
partToStroke ks "Return" = ks & ksKeys %~ Set.insert keyReturn
partToStroke ks "Space" = ks & ksKeys %~ Set.insert keySpace
partToStroke ks "Tab" = ks & ksKeys %~ Set.insert keyTab
-- Arrows
partToStroke ks "Up" = ks & ksKeys %~ Set.insert keyUp
partToStroke ks "Down" = ks & ksKeys %~ Set.insert keyDown
partToStroke ks "Left" = ks & ksKeys %~ Set.insert keyLeft
partToStroke ks "Right" = ks & ksKeys %~ Set.insert keyRight
-- Function keys
partToStroke ks "F1" = ks & ksKeys %~ Set.insert keyF1
partToStroke ks "F2" = ks & ksKeys %~ Set.insert keyF2
partToStroke ks "F3" = ks & ksKeys %~ Set.insert keyF3
partToStroke ks "F4" = ks & ksKeys %~ Set.insert keyF4
partToStroke ks "F5" = ks & ksKeys %~ Set.insert keyF5
partToStroke ks "F6" = ks & ksKeys %~ Set.insert keyF6
partToStroke ks "F7" = ks & ksKeys %~ Set.insert keyF7
partToStroke ks "F8" = ks & ksKeys %~ Set.insert keyF8
partToStroke ks "F9" = ks & ksKeys %~ Set.insert keyF9
partToStroke ks "F10" = ks & ksKeys %~ Set.insert keyF10
partToStroke ks "F11" = ks & ksKeys %~ Set.insert keyF11
partToStroke ks "F12" = ks & ksKeys %~ Set.insert keyF12
-- Other keys (numbers, letters, points, etc)
partToStroke ks txt
  | isTextValidCode txt = ks & ksKeys %~ Set.insert (KeyCode (ord txtHead))
  | otherwise = ks
  where
    txtHead = T.index txt 0

isTextValidCode :: Text -> Bool
isTextValidCode txt = validLen && isAscii txtHead && isPrint txtHead where
  validLen = T.length txt == 1
  txtHead = T.index txt 0

removeMods :: InputStatus -> InputStatus
removeMods status = status
  & L.keys %~ M.filterWithKey (\k v -> k `notElem` modKeys)

modKeys :: [KeyCode]
modKeys = [
    keyLAlt, keyRAlt, keyLCtrl, keyRCtrl, keyLGUI, keyRGUI, keyLShift, keyRShift
  ]
