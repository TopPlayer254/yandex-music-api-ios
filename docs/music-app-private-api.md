# Приватные зависимости оригинального Music.app

Источник: iOS 26.5.1, build 23F81. Бинарники не изменялись.

Полные списки в этом каталоге:

- [2892 уникальных импортируемых символа с библиотекой и бинарниками-потребителями](music-app-private-symbols.csv).
- [Все entitlements и значения XPC-разрешений по бинарникам](music-app-entitlements.json).

Повторить анализ из корня проекта:

```powershell
python tools/audit_music_private_api.py work/music-app-research/extracted/23F81__iPhone18,1/private/var/staged_system_apps/Music.app --output work/music-app-research/private-api
python -m unittest discover -s tools -p test_audit_music_private_api.py -v
```

## Результат проверки возможности бинарного патча

После уточнения задачи приоритет — сохранить оригинальный интерфейс Apple. Приватные UI-зависимости могут остаться; замене подлежат Apple-сервисы, сетевой бэкенд и привилегированные операции. Поэтому список ниже — инвентаризация, а не перечень библиотек для безусловного удаления.

Полная замена бэкенда в скомпилированном Music.app не реализована, модифицированный IPA не собран. Удаление списка приватных импортов не превращает оригинальный интерфейс в самостоятельный плеер. Необходимы реализации его зависимостей или восстановление и пересборка соответствующего кода; исходников приложения в IPSW нет.

В главном бинарнике 2708 импортов из приватных библиотек: 172 Objective-C типа, 741 символ Swift metadata/conformance, 1602 других Swift-символа и 193 функции/объекта данных. Это предварительная классификация по форме имён, а не декомпиляция всех мест использования.

Примеры жёстких зависимостей:

- `MusicModelBrickItem`, `MusicModelFlowcaseItem` и `MusicModelGridItem` наследуются от `MPModelObject`. Приватные модели используются непосредственно в UI, а не только внутри HTTP-клиента.
- MusicApplication импортирует metadata accessors `MediaCoreUI.MotionMode`, `MediaCoreUI.CircularProgressView.LineStyle`, `MusicKitInternal.GenericMusicItem` и `MusicKitInternal.LyricsResponse.Lyrics`. Эти импорты strong; пустая C-функция вместо accessor не возвращает требуемую Swift metadata.
- `LyricsX.SyncedLyricsViewController` хранит Swift-значения `LyricsX.Lyrics`, `LyricsSpecs`, timing provider и delegate. В его Objective-C-интерфейсе нет готового публичного метода установки текста/таймингов из нашей модели. Это не доказывает невозможность адаптера, но `NSClassFromString` с созданием контроллера сам по себе такой адаптер не реализует.

`MPModel*` также импортируются из публичного MediaPlayer.framework. Статус framework не делает каждый его символ публичным. В CSV всех импортов эти случаи требуют отдельного сравнения с SDK; они не включены автоматически в число 2892.

## Соответствия для реализации на публичных API

Эта таблица описывает границы необходимой замены. Она не означает, что оригинальные вызовы уже перенаправлены.

| Подсистема Apple | Имеющийся компонент нашего клиента | Что остаётся для оригинального UI |
| --- | --- | --- |
| MusicKitInternal, iTunesCloud, StoreServices: каталог и библиотека | `MusicService`, `YandexMusicService`, `BackendMusicService`, `CatalogStore` | Заменить схемы моделей и получение данных во всех экранах |
| MediaPlaybackCore, MediaRemote: очередь и команды | `PlayerStore`, AVPlayer, MPRemoteCommandCenter, MPNowPlayingInfoCenter | Заменить MPCPlayerResponse/Tracklist и наблюдение за состоянием |
| AuthKit, AppleIDSSOAuthentication: Apple Account | `AuthStore`, `YandexOAuthClient`, `KeychainTokenVault` | Удалить Apple Account-потоки и их side effects при старте |
| MusicLibrary, системные download/XPC-сервисы | `OfflineStore`, `DownloadsStore`, `MediaFileLoader` | Заменить системные идентификаторы и persistence, убрать системные XPC-вызовы |
| MusicUI, MediaCoreUI, MPUFoundation, приватные UI-классы | SwiftUI/UIKit из публичного SDK | Восстановить интерфейс и анимации либо реализовать совместимый ABI |
| CoreAnalytics, RecapPerformanceTesting | Не требуется | Удалить вызовы и инициаторы, не перенаправлять на другой сборщик |
| LyricsX | `Lyrics`, `LyricLineView`, `LyricsSynchronizer` в нашем коде | Восстановить параметры/поведение или полноценный адаптер Swift-моделей оригинала |

До реализации этой замены упаковка ZIP в IPA оставит те же зависимости. Тесты инструмента подтверждают разбор ordinals/imports, но не работоспособность клиента.

В 10 бинарниках найдены 63 приватных framework и `libMobileGestalt`, всего 64 уникальные библиотеки и 2892 уникальных импорта из них.

Это статические требования связывания. Они не доказывают выполнение каждого вызова. Полная классификация SPI внутри публичных frameworks требует сравнения с публичным SDK; такие импорты отдельно помечены `requires-public-sdk-symbol-check`.

## Количество импортов из приватных библиотек

| Бинарник | Импорты |
| --- | ---: |
| `Frameworks/MusicApplication.framework/MusicApplication` | 1217 |
| `Frameworks/MusicApplication.framework/XPCServices/MusicScriptUpdateService.xpc/MusicScriptUpdateService` | 950 |
| `Music` | 2708 |
| `PlugIns/MusicCoreSpotlightExtension.appex/MusicCoreSpotlightExtension` | 1 |
| `PlugIns/MusicMessagesApp.appex/MusicMessagesApp` | 975 |
| `PlugIns/MusicNotificationContentExtension.appex/MusicNotificationContentExtension` | 2 |
| `PlugIns/MusicWidgets.appex/MusicWidgets` | 1029 |
| `PlugIns/StoreFlowExtension.appex/StoreFlowExtension` | 25 |

## Все приватные библиотеки

### AXCoreUtilities

`/System/Library/PrivateFrameworks/AXCoreUtilities.framework/AXCoreUtilities`

Уникальных импортов: 1. Бинарников: 1.

### AXRuntime

`/System/Library/PrivateFrameworks/AXRuntime.framework/AXRuntime`

Уникальных импортов: 0. Бинарников с LC_LOAD_DYLIB: 1.

### AccessibilityUtilities

`/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/AccessibilityUtilities`

Уникальных импортов: 2. Бинарников: 1.

### AppSupport

`/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport`

Уникальных импортов: 1. Бинарников: 1.

### AppleAccountUI

`/System/Library/PrivateFrameworks/AppleAccountUI.framework/AppleAccountUI`

Уникальных импортов: 1. Бинарников: 1.

### AppleIDSSOAuthentication

`/System/Library/PrivateFrameworks/AppleIDSSOAuthentication.framework/AppleIDSSOAuthentication`

Уникальных импортов: 3. Бинарников: 2.

### AppleMediaServices

`/System/Library/PrivateFrameworks/AppleMediaServices.framework/AppleMediaServices`

Уникальных импортов: 30. Бинарников: 5.

### AppleMediaServicesUI

`/System/Library/PrivateFrameworks/AppleMediaServicesUI.framework/AppleMediaServicesUI`

Уникальных импортов: 9. Бинарников: 6.

### ApplePushService

`/System/Library/PrivateFrameworks/ApplePushService.framework/ApplePushService`

Уникальных импортов: 3. Бинарников: 5.

### AssistantServices

`/System/Library/PrivateFrameworks/AssistantServices.framework/AssistantServices`

Уникальных импортов: 1. Бинарников: 2.

### AsyncAlgorithmsInternal

`/System/Library/PrivateFrameworks/AsyncAlgorithmsInternal.framework/AsyncAlgorithmsInternal`

Уникальных импортов: 6. Бинарников: 1.

### AudioToolboxCore

`/System/Library/PrivateFrameworks/AudioToolboxCore.framework/AudioToolboxCore`

Уникальных импортов: 1. Бинарников: 5.

### AuthKit

`/System/Library/PrivateFrameworks/AuthKit.framework/AuthKit`

Уникальных импортов: 5. Бинарников: 2.

### AuthKitUI

`/System/Library/PrivateFrameworks/AuthKitUI.framework/AuthKitUI`

Уникальных импортов: 1. Бинарников: 2.

### CarKit

`/System/Library/PrivateFrameworks/CarKit.framework/CarKit`

Уникальных импортов: 1. Бинарников: 2.

### CarPlayServices

`/System/Library/PrivateFrameworks/CarPlayServices.framework/CarPlayServices`

Уникальных импортов: 1. Бинарников: 1.

### CarPlayUI

`/System/Library/PrivateFrameworks/CarPlayUI.framework/CarPlayUI`

Уникальных импортов: 92. Бинарников: 1.

### Celestial

`/System/Library/PrivateFrameworks/Celestial.framework/Celestial`

Уникальных импортов: 0. Бинарников с LC_LOAD_DYLIB: 1.

### ClarityFoundation

`/System/Library/PrivateFrameworks/ClarityFoundation.framework/ClarityFoundation`

Уникальных импортов: 1. Бинарников: 1.

### CollectionsInternal

`/System/Library/PrivateFrameworks/CollectionsInternal.framework/CollectionsInternal`

Уникальных импортов: 10. Бинарников: 1.

### ControlCenterServices

`/System/Library/PrivateFrameworks/ControlCenterServices.framework/ControlCenterServices`

Уникальных импортов: 1. Бинарников: 1.

### CoreAnalytics

`/System/Library/PrivateFrameworks/CoreAnalytics.framework/CoreAnalytics`

Уникальных импортов: 2. Бинарников: 5.

### CoreBrightness

`/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness`

Уникальных импортов: 1. Бинарников: 5.

### FeatureFlags

`/System/Library/PrivateFrameworks/FeatureFlags.framework/FeatureFlags`

Уникальных импортов: 4. Бинарников: 5.

### IconFoundation

`/System/Library/PrivateFrameworks/IconFoundation.framework/IconFoundation`

Уникальных импортов: 1. Бинарников: 1.

### IconServices

`/System/Library/PrivateFrameworks/IconServices.framework/IconServices`

Уникальных импортов: 4. Бинарников: 1.

### InAppFeedback

`/System/Library/PrivateFrameworks/InAppFeedback.framework/InAppFeedback`

Уникальных импортов: 11. Бинарников: 1.

### InAppMessages

`/System/Library/PrivateFrameworks/InAppMessages.framework/InAppMessages`

Уникальных импортов: 3. Бинарников: 1.

### InAppMessagesCore

`/System/Library/PrivateFrameworks/InAppMessagesCore.framework/InAppMessagesCore`

Уникальных импортов: 6. Бинарников: 2.

### MPUFoundation

`/System/Library/PrivateFrameworks/MPUFoundation.framework/MPUFoundation`

Уникальных импортов: 2. Бинарников: 2.

### ManagedConfiguration

`/System/Library/PrivateFrameworks/ManagedConfiguration.framework/ManagedConfiguration`

Уникальных импортов: 8. Бинарников: 5.

### MediaControls

`/System/Library/PrivateFrameworks/MediaControls.framework/MediaControls`

Уникальных импортов: 2. Бинарников: 5.

### MediaCoreUI

`/System/Library/PrivateFrameworks/MediaCoreUI.framework/MediaCoreUI`

Уникальных импортов: 250. Бинарников: 5.

### MediaPlaybackCore

`/System/Library/PrivateFrameworks/MediaPlaybackCore.framework/MediaPlaybackCore`

Уникальных импортов: 44. Бинарников: 5.

### MediaPlayerUI

`/System/Library/PrivateFrameworks/MediaPlayerUI.framework/MediaPlayerUI`

Уникальных импортов: 1. Бинарников: 5.

### MediaRemote

`/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote`

Уникальных импортов: 35. Бинарников: 5.

### MediaServices

`/System/Library/PrivateFrameworks/MediaServices.framework/MediaServices`

Уникальных импортов: 15. Бинарников: 5.

### MusicCarDisplayUI

`/System/Library/PrivateFrameworks/MusicCarDisplayUI.framework/MusicCarDisplayUI`

Уникальных импортов: 36. Бинарников: 1.

### MusicKitInternal

`/System/Library/PrivateFrameworks/MusicKitInternal.framework/MusicKitInternal`

Уникальных импортов: 1441. Бинарников: 5.

### MusicLibrary

`/System/Library/PrivateFrameworks/MusicLibrary.framework/MusicLibrary`

Уникальных импортов: 1. Бинарников: 1.

### MusicUI

`/System/Library/PrivateFrameworks/MusicUI.framework/MusicUI`

Уникальных импортов: 464. Бинарников: 2.

### OnBoardingKit

`/System/Library/PrivateFrameworks/OnBoardingKit.framework/OnBoardingKit`

Уникальных импортов: 1. Бинарников: 1.

### Radio

`/System/Library/PrivateFrameworks/Radio.framework/Radio`

Уникальных импортов: 2. Бинарников: 5.

### RecapPerformanceTesting

`/System/Library/PrivateFrameworks/RecapPerformanceTesting.framework/RecapPerformanceTesting`

Уникальных импортов: 2. Бинарников: 1.

### RunningBoardServices

`/System/Library/PrivateFrameworks/RunningBoardServices.framework/RunningBoardServices`

Уникальных импортов: 4. Бинарников: 3.

### SAObjects

`/System/Library/PrivateFrameworks/SAObjects.framework/SAObjects`

Уникальных импортов: 9. Бинарников: 2.

### SafariCore

`/System/Library/PrivateFrameworks/SafariCore.framework/SafariCore`

Уникальных импортов: 1. Бинарников: 1.

### ShareSheet

`/System/Library/PrivateFrameworks/ShareSheet.framework/ShareSheet`

Уникальных импортов: 23. Бинарников: 5.

### SiriActivation

`/System/Library/PrivateFrameworks/SiriActivation.framework/SiriActivation`

Уникальных импортов: 2. Бинарников: 1.

### SiriKitInvocation

`/System/Library/PrivateFrameworks/SiriKitInvocation.framework/SiriKitInvocation`

Уникальных импортов: 3. Бинарников: 2.

### SocialLayer

`/System/Library/PrivateFrameworks/SocialLayer.framework/SocialLayer`

Уникальных импортов: 3. Бинарников: 2.

### SpringBoardServices

`/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices`

Уникальных импортов: 1. Бинарников: 1.

### SpringBoardUIServices

`/System/Library/PrivateFrameworks/SpringBoardUIServices.framework/SpringBoardUIServices`

Уникальных импортов: 0. Бинарников с LC_LOAD_DYLIB: 1.

### StoreServices

`/System/Library/PrivateFrameworks/StoreServices.framework/StoreServices`

Уникальных импортов: 30. Бинарников: 6.

### UIFoundation

`/System/Library/PrivateFrameworks/UIFoundation.framework/UIFoundation`

Уникальных импортов: 25. Бинарников: 5.

### UIKitServices

`/System/Library/PrivateFrameworks/UIKitServices.framework/UIKitServices`

Уникальных импортов: 1. Бинарников: 1.

### VFX

`/System/Library/PrivateFrameworks/VFX.framework/VFX`

Уникальных импортов: 0. Бинарников с LC_LOAD_DYLIB: 2.

### _MusicKitInternal_MediaPlaybackCore

`/System/Library/PrivateFrameworks/_MusicKitInternal_MediaPlaybackCore.framework/_MusicKitInternal_MediaPlaybackCore`

Уникальных импортов: 30. Бинарников: 5.

### _MusicKitInternal_MediaPlayer

`/System/Library/PrivateFrameworks/_MusicKitInternal_MediaPlayer.framework/_MusicKitInternal_MediaPlayer`

Уникальных импортов: 31. Бинарников: 5.

### _MusicKitInternal_SwiftUI

`/System/Library/PrivateFrameworks/_MusicKitInternal_SwiftUI.framework/_MusicKitInternal_SwiftUI`

Уникальных импортов: 95. Бинарников: 5.

### iTunesCloud

`/System/Library/PrivateFrameworks/iTunesCloud.framework/iTunesCloud`

Уникальных импортов: 94. Бинарников: 6.

### iTunesStore

`/System/Library/PrivateFrameworks/iTunesStore.framework/iTunesStore`

Уникальных импортов: 3. Бинарников: 2.

### iTunesStoreUI

`/System/Library/PrivateFrameworks/iTunesStoreUI.framework/iTunesStoreUI`

Уникальных импортов: 17. Бинарников: 1.

### libMobileGestalt.dylib

`/usr/lib/libMobileGestalt.dylib`

Уникальных импортов: 14. Бинарников: 5.

## Системные права и XPC

Полный список значений — в [music-app-entitlements.json](music-app-entitlements.json). Ключи с `.private` и `platform-application` выписаны ниже; остальные права сохранены для проверки provisioning profile, их нельзя автоматически считать публичными или приватными.

### Frameworks/MusicApplication.framework/XPCServices/MusicScriptUpdateService.xpc/MusicScriptUpdateService

- `com.apple.private.security.container-required`

### Music

- `com.apple.atc.private`
- `com.apple.authkit.client.private`
- `com.apple.itunescloudd.private`
- `com.apple.itunesstored.private`
- `com.apple.private.CarPlayUIServices.status-bar-style`
- `com.apple.private.CoreAuthentication.SPI`
- `com.apple.private.FairPlayIOKitUserClient.access`
- `com.apple.private.MobileGestalt.AllowedProtectedKeys`
- `com.apple.private.accounts.allaccounts`
- `com.apple.private.applemediaservices`
- `com.apple.private.appstored`
- `com.apple.private.bmk.allow`
- `com.apple.private.carkit.app`
- `com.apple.private.cfnetwork.har-capture-amp`
- `com.apple.private.contacts`
- `com.apple.private.controlcenter.service.moduleidentifiers`
- `com.apple.private.coreaudio.viewInterruptorName.allow`
- `com.apple.private.coreservices.canmaplsdatabase`
- `com.apple.private.corewifi`
- `com.apple.private.hid.client.event-dispatch.internal`
- `com.apple.private.hsa-authentication-processing`
- `com.apple.private.iad.background-client`
- `com.apple.private.iad.privileged-client`
- `com.apple.private.ids.phone-number-authentication`
- `com.apple.private.ids.registration`
- `com.apple.private.ids.remoteurlconnection`
- `com.apple.private.ids.session`
- `com.apple.private.imcore.imremoteurlconnection`
- `com.apple.private.in-app-payments`
- `com.apple.private.jetpackassetd`
- `com.apple.private.privacy.accounting.write`
- `com.apple.private.rtcreportingd`
- `com.apple.private.security.container-required`
- `com.apple.private.security.restricted-application-groups`
- `com.apple.private.security.system-application`
- `com.apple.private.sociallayer.highlights`
- `com.apple.private.swc.additional-service-details-consumer`
- `com.apple.private.swc.system-app`
- `com.apple.private.tcc.allow`
- `com.apple.private.tcc.allow-or-regional-prompt`
- `com.apple.private.ubiquity-additional-kvstore-identifiers`
- `platform-application`

Запрашиваемые Mach/XPC-сервисы:

- `com.apple.iTunesCloud.SharedListeningConnectionService`
- `com.apple.private.corewifi-xpc`
- `com.apple.carkit.app.service`
- `com.apple.sharing.sharesheetuserdefaults`
- `com.apple.nanosystemsettings`
- `com.apple.adid`
- `com.apple.ak.anisette.xpc`
- `com.apple.askpermissiond`
- `com.apple.familycircle.agent`
- `com.apple.hsa-authentication-server`
- `com.apple.mediaartworkd.xpc`
- `com.apple.MediaPlayer.MPRadioControllerServer`
- `com.apple.rtcreportingd`
- `com.apple.storebookkeeperd.xpc`
- `com.apple.atc.xpc`
- `com.apple.atc.xpc.downloadprogress`
- `com.apple.atc.xpc.runkeeplocaltask`
- `com.apple.PairingManager`
- `com.apple.itunescloudd.playactivity`
- `com.apple.nanoprefsync`
- `com.apple.itunescloud.delegation-provider`
- `com.apple.itunescloud.delegate-account-store`
- `com.apple.coremedia.endpointpicker.xpc`
- `com.apple.coremedia.routediscoverer.xpc`
- `com.apple.coremedia.routingcontext.xpc`
- `com.apple.coremedia.endpointremotecontrolsession.xpc`
- `com.apple.bulletinboard.observerconnection`
- `com.apple.symptom_analytics`
- `com.apple.itunescloud.contenttaste`
- `com.apple.lsd.modifydb`
- `com.apple.itunescloud.in-app-message-service`
- `com.apple.itunescloud.music-subscription-status-service`
- `com.apple.identityservicesd.embedded.auth`
- `com.apple.itunescloud.media-app-banner-service`
- `com.apple.itunescloud.remote-request-execution-service`
- `com.apple.siri.activation.service`
- `com.apple.Music.MusicScriptUpdateService`
- `com.apple.AppleMediaServicesUIDynamicService`
- `com.apple.passd.in-app-payment`
- `com.apple.xpc.amsaccountsd`
- `com.apple.coreidvd.proofing`
- `com.apple.sociallayerd`
- `com.apple.aa.custodian.xpc`
- `com.apple.extensionkitservice`
- `com.apple.aa.inheritance.xpc`
- `com.apple.cdp.daemon`
- `com.apple.controlcenter.remoteservice`
- `com.apple.symptom_diagnostics`
- `com.apple.siri.external_request`
- `com.apple.itunescloud.library-auth-token-provider`
- `com.apple.siri.analytics.assistant`
- `com.apple.identityservicesd.embedded.auth`
- `com.apple.passd.library`
- `com.apple.passd.payment`
- `com.apple.appstored.xpc`
- `com.apple.appstored.xpc.request`
- `com.apple.passd.account`
- `com.apple.passd.peer-payment`
- `com.apple.lsd.xpc`
- `com.apple.mobile.keybagd.xpc`
- `com.apple.CarPlayApp.status-bar-service`
- `com.apple.CarPlayApp.service`
- `com.apple.powerlog.plxpclogger.xpc`
- `com.apple.PerfPowerTelemetryClientRegistrationService`
- `com.apple.surfboard.scenesessionservice`
- `com.apple.devicesharing.guestusermodeservice`
- `com.apple.backlightd`
- `com.apple.absd`
- `com.apple.aa.daemon.xpc`
- `com.apple.fairplayd.xpc`
- `com.apple.timed.xpc`
- `com.apple.jetpackassetd.xpc`

### PlugIns/MediaPicker.appex/MediaPicker

- `com.apple.atc.private`
- `com.apple.authkit.client.private`
- `com.apple.itunesstored.private`
- `com.apple.private.accounts.allaccounts`
- `com.apple.private.applemediaservices`
- `com.apple.private.coreservices.canmaplsdatabase`
- `com.apple.private.iad.background-client`
- `com.apple.private.iad.privileged-client`
- `com.apple.private.rtcreportingd`
- `com.apple.private.security.container-required`
- `com.apple.private.tcc.allow`
- `com.apple.private.tcc.allow-or-regional-prompt`

Запрашиваемые Mach/XPC-сервисы:

- `com.apple.nanosystemsettings`
- `com.apple.adid`
- `com.apple.ak.anisette.xpc`
- `com.apple.askpermissiond`
- `com.apple.familycircle.agent`
- `com.apple.hsa-authentication-server`
- `com.apple.mediaartworkd.xpc`
- `com.apple.MediaPlayer.MPRadioControllerServer`
- `com.apple.rtcreportingd`
- `com.apple.storebookkeeperd.xpc`
- `com.apple.atc.xpc`
- `com.apple.atc.xpc.downloadprogress`
- `com.apple.atc.xpc.runkeeplocaltask`
- `com.apple.PairingManager`
- `com.apple.itunescloudd.playactivity`
- `com.apple.nanoprefsync`
- `com.apple.itunescloud.delegation-provider`
- `com.apple.itunescloud.delegate-account-store`
- `com.apple.coremedia.endpointpicker.xpc`
- `com.apple.coremedia.routediscoverer.xpc`
- `com.apple.coremedia.routingcontext.xpc`
- `com.apple.coremedia.endpointremotecontrolsession.xpc`
- `com.apple.bulletinboard.observerconnection`
- `com.apple.symptom_analytics`
- `com.apple.itunescloud.contenttaste`
- `com.apple.lsd.modifydb`
- `com.apple.itunescloud.in-app-message-service`
- `com.apple.itunescloud.music-subscription-status-service`
- `com.apple.identityservicesd.embedded.auth`
- `com.apple.itunescloud.media-app-banner-service`
- `com.apple.itunescloud.remote-request-execution-service`
- `com.apple.absd`

### PlugIns/MusicCoreSpotlightExtension.appex/MusicCoreSpotlightExtension

- `com.apple.private.tcc.allow`

### PlugIns/MusicMessagesApp.appex/MusicMessagesApp

- `com.apple.authkit.client.private`
- `com.apple.itunesstored.private`
- `com.apple.private.attribution.implicitly-assumed-identity`
- `com.apple.private.tcc.allow`

Запрашиваемые Mach/XPC-сервисы:

- `com.apple.ak.anisette.xpc`

### PlugIns/MusicNotificationContentExtension.appex/MusicNotificationContentExtension

- `com.apple.private.applemediaservices`
- `com.apple.private.coreservices.canmaplsdatabase`
- `com.apple.private.security.container-required`

### PlugIns/MusicWidgets.appex/MusicWidgets

- `com.apple.authkit.client.private`
- `com.apple.itunesstored.private`
- `com.apple.private.applemediaservices`
- `com.apple.private.attribution.implicitly-assumed-identity`
- `com.apple.private.coreservices.canmaplsdatabase`
- `com.apple.private.corewifi`
- `com.apple.private.tcc.allow`

Запрашиваемые Mach/XPC-сервисы:

- `com.apple.adid`
- `com.apple.ak.anisette.xpc`
- `com.apple.itunescloud.contenttaste`
- `com.apple.itunescloud.delegation-provider`
- `com.apple.itunescloud.delegate-account-store`
- `com.apple.itunescloud.music-subscription-status-service`
- `com.apple.itunescloud.remote-request-execution-service`
- `com.apple.itunescloudd.playactivity`
- `com.apple.mediaartworkd.xpc`
- `com.apple.siri.VoiceShortcuts.xpc`
- `com.apple.linkd.registry`
- `com.apple.private.corewifi-xpc`

### PlugIns/StoreFlowExtension.appex/StoreFlowExtension

- `com.apple.itunesstored.private`
- `com.apple.private.CoreAuthentication.SPI`
- `com.apple.private.accounts.allaccounts`
- `com.apple.private.applemediaservices`
- `com.apple.private.bmk.allow`
- `com.apple.private.coreservices.canmaplsdatabase`
- `com.apple.private.familycircle`
- `com.apple.private.hsa-authentication-processing`
- `com.apple.private.mobilesms.messages-recipient-vetting`
- `com.apple.private.tcc.allow`

Запрашиваемые Mach/XPC-сервисы:

- `com.apple.AppleMediaServicesUIDynamicService`
- `com.apple.absd`
- `com.apple.adid`
- `com.apple.ak.anisette.xpc`
- `com.apple.askpermissiond`
- `com.apple.cdp.daemon`
- `com.apple.hsa-authentication-server`
- `com.apple.itunescloud.music-subscription-status-service`
- `com.apple.mobile.keybagd.xpc`
- `com.apple.passd.in-app-payment`
- `com.apple.passd.library`
- `com.apple.xpc.amsaccountsd`

## Ограничения замены

Удаление LC_LOAD_DYLIB изменяет нумерацию library ordinals и не переписывает nlist/chained fixups, код, Swift metadata или Objective-C superclasses. Подмена импортов пустыми функциями не реализует ABI классов, протоколов и структур.

Данный отчёт не является модифицированным приложением. Замена Apple backend и проверка запуска не выполнены.

Формат chained imports: https://github.com/apple-oss-distributions/dyld/blob/main/include/mach-o/fixup-chains.h
Provisioning и entitlements: https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles
