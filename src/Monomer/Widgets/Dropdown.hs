{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RecordWildCards #-}

module Monomer.Widgets.Dropdown (
  DropdownCfg,
  dropdown,
  dropdown_,
  dropdownV,
  dropdownV_,
  dropdownD_
) where

import Control.Applicative ((<|>))
import Control.Lens (ALens', (&), (^#), (#~), (^.))
import Control.Monad
import Data.Default
import Data.List (foldl')
import Data.Maybe (fromJust, fromMaybe, isJust)
import Data.Sequence (Seq(..), (<|), (|>))
import Data.Text (Text)
import Data.Typeable (Typeable, cast)

import qualified Data.Sequence as Seq

import Monomer.Widgets.Container
import Monomer.Widgets.Label
import Monomer.Widgets.ListView

data DropdownCfg s e a = DropdownCfg {
  _ddcOnChange :: [a -> e],
  _ddcOnChangeReq :: [WidgetRequest s],
  _ddcOnChangeIdx :: [Int -> a -> e],
  _ddcOnChangeReqIdx :: [Int -> WidgetRequest s],
  _ddcMaxHeight :: Maybe Double,
  _ddcBgColor :: Maybe Color,
  _ddcSelectedStyle :: Maybe StyleState,
  _ddcHoverStyle :: Maybe StyleState,
  _ddcHighlightedColor :: Maybe Color
}

instance Default (DropdownCfg s e a) where
  def = DropdownCfg {
    _ddcOnChange = [],
    _ddcOnChangeReq = [],
    _ddcOnChangeIdx = [],
    _ddcOnChangeReqIdx = [],
    _ddcMaxHeight = Nothing,
    _ddcBgColor = Nothing,
    _ddcSelectedStyle = Nothing,
    _ddcHoverStyle = Nothing,
    _ddcHighlightedColor = Nothing
  }

instance Semigroup (DropdownCfg s e a) where
  (<>) t1 t2 = DropdownCfg {
    _ddcOnChange = _ddcOnChange t1 <> _ddcOnChange t2,
    _ddcOnChangeReq = _ddcOnChangeReq t1 <> _ddcOnChangeReq t2,
    _ddcOnChangeIdx = _ddcOnChangeIdx t1 <> _ddcOnChangeIdx t2,
    _ddcOnChangeReqIdx = _ddcOnChangeReqIdx t1 <> _ddcOnChangeReqIdx t2,
    _ddcMaxHeight = _ddcMaxHeight t2 <|> _ddcMaxHeight t1,
    _ddcBgColor = _ddcBgColor t2 <|> _ddcBgColor t1,
    _ddcSelectedStyle = _ddcSelectedStyle t2 <|> _ddcSelectedStyle t1,
    _ddcHoverStyle = _ddcHoverStyle t2 <|> _ddcHoverStyle t1,
    _ddcHighlightedColor = _ddcHighlightedColor t2 <|> _ddcHighlightedColor t1
  }

instance Monoid (DropdownCfg s e a) where
  mempty = def

instance OnChange (DropdownCfg s e a) a e where
  onChange fn = def {
    _ddcOnChange = [fn]
  }

instance OnChangeReq (DropdownCfg s e a) s where
  onChangeReq req = def {
    _ddcOnChangeReq = [req]
  }

instance OnChangeIdx (DropdownCfg s e a) a e where
  onChangeIdx fn = def {
    _ddcOnChangeIdx = [fn]
  }

instance OnChangeReqIdx (DropdownCfg s e a) s where
  onChangeReqIdx req = def {
    _ddcOnChangeReqIdx = [req]
  }

instance BgColor (DropdownCfg s e a) where
  bgColor col = def {
    _ddcBgColor = Just col
  }

instance SelectedStyle (DropdownCfg s e a) where
  selectedStyle style = def {
    _ddcSelectedStyle = Just style
  }

instance HoverStyle (DropdownCfg s e a) where
  hoverStyle style = def {
    _ddcHoverStyle = Just style
  }

instance HighlightedColor (DropdownCfg s e a) where
  highlightedColor color = def {
    _ddcHighlightedColor = Just color
  }

newtype DropdownState = DropdownState {
  _isOpen :: Bool
}

newtype DropdownMessage
  = OnChangeMessage Int
  deriving Typeable

dropdown
  :: (Traversable t, Eq a)
  => ALens' s a
  -> t a
  -> (a -> Text)
  -> (a -> WidgetInstance s e)
  -> WidgetInstance s e
dropdown field items makeMain makeRow = newInst where
  newInst = dropdown_ field items makeMain makeRow def

dropdown_
  :: (Traversable t, Eq a)
  => ALens' s a
  -> t a
  -> (a -> Text)
  -> (a -> WidgetInstance s e)
  -> [DropdownCfg s e a]
  -> WidgetInstance s e
dropdown_ field items makeMain makeRow configs = newInst where
  widgetData = WidgetLens field
  newInst = dropdownD_ widgetData items makeMain makeRow configs

dropdownV
  :: (Traversable t, Eq a)
  => a
  -> (a -> e)
  -> t a
  -> (a -> Text)
  -> (a -> WidgetInstance s e)
  -> WidgetInstance s e
dropdownV value handler items makeMain makeRow = newInst where
  newInst = dropdownV_ value handler items makeMain makeRow def

dropdownV_
  :: (Traversable t, Eq a)
  => a
  -> (a -> e)
  -> t a
  -> (a -> Text)
  -> (a -> WidgetInstance s e)
  -> [DropdownCfg s e a]
  -> WidgetInstance s e
dropdownV_ value handler items makeMain makeRow configs = newInst where
  newConfigs = onChange handler : configs
  newInst = dropdownD_ (WidgetValue value) items makeMain makeRow newConfigs

dropdownD_
  :: (Traversable t, Eq a)
  => WidgetData s a
  -> t a
  -> (a -> Text)
  -> (a -> WidgetInstance s e)
  -> [DropdownCfg s e a]
  -> WidgetInstance s e
dropdownD_ widgetData items makeMain makeRow configs = makeInstance widget where
  config = mconcat configs
  newState = DropdownState False
  newItems = foldl' (|>) Empty items
  widget = makeDropdown widgetData newItems makeMain makeRow config newState

makeInstance :: Widget s e -> WidgetInstance s e
makeInstance widget = (defaultWidgetInstance "dropdown" widget) {
  _wiFocusable = True
}

makeDropdown
  :: (Eq a)
  => WidgetData s a
  -> Seq a
  -> (a -> Text)
  -> (a -> WidgetInstance s e)
  -> DropdownCfg s e a
  -> DropdownState
  -> Widget s e
makeDropdown widgetData items makeMain makeRow config state = widget where
  baseWidget = createContainer def {
    containerInit = init,
    containerGetState = makeState state,
    containerMerge = merge,
    containerHandleEvent = handleEvent,
    containerHandleMessage = handleMessage,
    containerGetSizeReq = getSizeReq,
    containerResize = resize
  }
  widget = baseWidget {
    widgetRender = render
  }

  isOpen = _isOpen state
  currentValue wenv = widgetDataGet (_weModel wenv) widgetData

  createDropdown wenv newState widgetInst = newInstance where
    selected = currentValue wenv
    path = _wiPath widgetInst
    listViewInst = makeListView widgetData items makeRow config path selected
    newWidget = makeDropdown widgetData items makeMain makeRow config newState
    newInstance = widgetInst {
      _wiWidget = newWidget,
      _wiChildren = Seq.singleton listViewInst
    }

  init wenv widgetInst = resultWidget $ createDropdown wenv state widgetInst

  merge wenv oldState newInst = result where
    newState = fromMaybe state (useState oldState)
    result = resultWidget $ createDropdown wenv newState newInst

  handleEvent wenv target evt widgetInst = case evt of
    Click point _
      | openRequired point widgetInst -> Just $ openDropdown wenv widgetInst
      | closeRequired point widgetInst -> Just $ closeDropdown wenv widgetInst
    KeyAction mode code status
      | isKeyDown code && not isOpen -> Just $ openDropdown wenv widgetInst
      | isKeyEsc code && isOpen -> Just $ closeDropdown wenv widgetInst
    _
      | not isOpen -> Just $ resultReqs [IgnoreChildrenEvents] widgetInst
      | otherwise -> Nothing

  openRequired point widgetInst = not isOpen && inViewport where
    inViewport = pointInRect point (_wiViewport widgetInst)

  closeRequired point widgetInst = isOpen && not inOverlay where
    inOverlay = case Seq.lookup 0 (_wiChildren widgetInst) of
      Just inst -> pointInRect point (_wiViewport inst)
      Nothing -> False

  openDropdown wenv widgetInst = resultReqs requests newInstance where
    selected = currentValue wenv
    selectedIdx = fromMaybe 0 (Seq.elemIndexL selected items)
    newState = DropdownState True
    newInstance = widgetInst {
      _wiWidget = makeDropdown widgetData items makeMain makeRow config newState
    }
    path = _wiPath widgetInst
    lvPath = firstChildPath widgetInst
    requests = [SetOverlay path, SetFocus lvPath]

  closeDropdown wenv widgetInst = resultReqs requests newInstance where
    path = _wiPath widgetInst
    newState = DropdownState False
    newInstance = widgetInst {
      _wiWidget = makeDropdown widgetData items makeMain makeRow config newState
    }
    requests = [ResetOverlay, SetFocus path]

  handleMessage wenv target message widgetInst = cast message
    >>= \(OnChangeMessage idx) -> Seq.lookup idx items
    >>= \value -> Just $ onChange wenv idx value widgetInst

  onChange wenv idx item widgetInst = result where
    WidgetResult reqs events newInstance = closeDropdown wenv widgetInst
    newReqs = Seq.fromList $ widgetDataSet widgetData item
      ++ _ddcOnChangeReq config
      ++ fmap ($ idx) (_ddcOnChangeReqIdx config)
    newEvents = Seq.fromList $ fmap ($ item) (_ddcOnChange config)
      ++ fmap (\fn -> fn idx item) (_ddcOnChangeIdx config)
    result = WidgetResult (reqs <> newReqs) (events <> newEvents) newInstance

  getSizeReq wenv widgetInst children = sizeReq where
    style = instanceStyle wenv widgetInst
    Size w h = getTextSize wenv style (dropdownLabel wenv)
    factor = 1
    sizeReq = (FlexSize w factor, FixedSize h)

  resize wenv viewport renderArea children widgetInst = resized where
    Size winW winH = _weAppWindowSize wenv
    Rect rx ry rw rh = renderArea
    dropdownY dh
      | ry + rh + dh <= winH = ry + rh
      | otherwise = ry - dh
    area = case Seq.lookup 0 children of
      Just child -> (oViewport, oRenderArea) where
        reqHeight = getMinSizeReq . _wiSizeReqH $ child
        maxHeight = min reqHeight $ fromMaybe 200 (_ddcMaxHeight config)
        oViewport = viewport {
          _rY = dropdownY maxHeight,
          _rH = maxHeight
        }
        oRenderArea = renderArea {
          _rY = dropdownY maxHeight,
          _rH = maxHeight
        }
      Nothing -> (viewport, renderArea)
    assignedArea = Seq.singleton area
    resized = (widgetInst, assignedArea)

  render renderer wenv widgetInst@WidgetInstance{..} = do
    drawStyledBackground renderer renderArea style
    drawStyledText_ renderer renderArea style (dropdownLabel wenv)

    when (isOpen && isJust listViewOverlay) $
      createOverlay renderer $
        renderOverlay renderer wenv (fromJust listViewOverlay)
    where
      listViewOverlay = Seq.lookup 0 _wiChildren
      renderArea = _wiRenderArea
      style = instanceStyle wenv widgetInst

  renderOverlay renderer wenv overlayInstance = renderAction where
    widget = _wiWidget overlayInstance
    renderAction = widgetRender widget renderer wenv overlayInstance

  dropdownLabel wenv = makeMain $ currentValue wenv

makeListView
  :: (Eq a)
  => WidgetData s a
  -> Seq a
  -> (a -> WidgetInstance s e)
  -> DropdownCfg s e a
  -> Path
  -> a
  -> WidgetInstance s e
makeListView value items makeRow config path selected = listViewInst where
  DropdownCfg{..} = config
  lvConfig = [
      onChangeReqIdx (SendMessage path . OnChangeMessage),
      setStyle _ddcSelectedStyle selectedStyle,
      setStyle _ddcHoverStyle hoverStyle,
      maybe def highlightedColor _ddcHighlightedColor
    ]
  bgCol = fromMaybe black _ddcBgColor
  listViewInst = listViewD_ value items makeRow lvConfig `style` [bgColor bgCol]

setStyle :: (Default a) => Maybe StyleState -> (StyleState -> a) -> a
setStyle Nothing _ = def
setStyle (Just st) fn = fn st