{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Tutorial08_Themes where

import Control.Lens
import Data.Text (Text)
import Monomer
import Monomer.Core.Themes.BaseTheme
import TextShow

import qualified Monomer.Lens as L

data ActiveTheme
  = DarkTheme
  | LightTheme
  | CustomTheme
  deriving (Eq, Enum, Show)

data AppModel = AppModel {
  _clickCount :: Int,
  _currentTheme :: ActiveTheme
} deriving (Eq, Show)

data AppEvent
  = AppInit
  | AppIncrease
  deriving (Eq, Show)

makeLenses 'AppModel

buildUI
  :: WidgetEnv AppModel AppEvent
  -> AppModel
  -> WidgetNode AppModel AppEvent
buildUI wenv model = widgetTree where
  theme = case model ^. currentTheme of
    DarkTheme -> darkTheme
    LightTheme -> lightTheme
    CustomTheme -> customTheme
  widgetTree = themeSwitch_ theme [themeClearBg] $ vstack [
      hstack [
        label "Select theme:",
        spacer,
        textDropdownS currentTheme (enumFrom (toEnum 0))
      ],
      spacer,
      separatorLine,
      spacer,
      label "Number",
      spacer,
      hstack [
        box $ hslider clickCount 0 100,
        spacer,
        numericField_ clickCount [minValue 0, maxValue 100]
      ],
      spacer,
      hstack [
        label $ "Click count: " <> showt (model ^. clickCount),
        spacer,
        button "Increase count" AppIncrease,
        spacer,
        mainButton "Increase count" AppIncrease
      ]
    ] `style` [padding 20]

handleEvent
  :: WidgetEnv AppModel AppEvent
  -> WidgetNode AppModel AppEvent
  -> AppModel
  -> AppEvent
  -> [AppEventResponse AppModel AppEvent]
handleEvent wenv node model evt = case evt of
  AppInit -> []
  AppIncrease -> [Model (model & clickCount +~ 1)]

customTheme :: Theme
customTheme = baseTheme darkThemeColors {
  btnMainBgBasic = orange
}

main08 :: IO ()
main08 = do
  startApp model handleEvent buildUI config
  where
    config = [
      appWindowTitle "Tutorial 08 - Themes",
      appTheme darkTheme,
      appFontDef "Regular" "./assets/fonts/Roboto-Regular.ttf",
      appInitEvent AppInit
      ]
    model = AppModel 0 LightTheme