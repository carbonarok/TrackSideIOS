# TrackSide for iOS

Live UK train times on iPhone, from your own
[trackside](https://github.com/carbonarok/trackside) server.

- **Departure and arrival boards** for any station, updating live.
- **Train pages** with every stop, platform, delay and the train's position.
- **Saved routes** with several legs, which work out the best trains and
  connections for you.
- **Live Activities** on the lock screen and Dynamic Island for each leg of a
  journey, kept current in the background by push.
- **Notifications** for platform changes, cancellations and delays.
- **Widgets** for a station's departures, and **Shortcuts** actions.
- **Journey history.**

> [!WARNING]
> Like trackside itself, this was built quickly with a lot of help from an AI
> coding assistant. Expect rough edges, and check official sources before
> relying on a connection.

## You need a server

TrackSide has no data of its own. It shows whatever a trackside server
serves, so you either
[run your own](https://github.com/carbonarok/trackside#quick-start) or use one
someone shares with you. On first launch the app asks for:

- **The server's address,** such as `trains.example.com` or
  `http://192.168.1.10:8080`. Without `http://` the app uses HTTPS. Plain
  HTTP only works for addresses on your local network.
- **An API key,** if the server was started with `API_KEY`. Leave it empty
  for an open server.

Change either later under **Settings → Server**. The widgets use the same
server.

## Building it

You need Xcode 26 or later. The app targets iOS 26.

1. **Set your team and bundle ID prefix.**

   ```bash
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   ```

   Edit `Config/Local.xcconfig`:

   ```
   DEVELOPMENT_TEAM = ABCDE12345     // your team ID
   BUNDLE_ID_PREFIX = com.yourname   // a reverse domain you control
   ```

   Every identifier is built from the prefix, so you don't need to edit the
   project:

   | | |
   |---|---|
   | App | `$(BUNDLE_ID_PREFIX).TrackSideIOS` |
   | Widgets | `$(BUNDLE_ID_PREFIX).TrackSideIOS.TrackSideWidgets` |
   | App Group | `group.$(BUNDLE_ID_PREFIX).TrackSideIOS` |

   `Local.xcconfig` is ignored by git, so your team never ends up in a
   commit.

2. **Open `TrackSideIOS.xcodeproj` and run.** With automatic signing, Xcode
   registers the bundle IDs and the App Group the first time. From the
   command line, add `-allowProvisioningUpdates` to `xcodebuild`.

**The Simulator** runs everything except push: it can't get push tokens, so
Live Activities only update while the app is open, and there are no
notifications.

**A free Apple ID (Personal Team)** can install the app on your own phone,
but can't use push notifications. Remove the Push Notifications capability
(the `aps-environment` entitlement) to build with one.

## Live Activity pushes

To keep Live Activities current while the app is in the background, the
server pushes updates through Apple's push service. That takes:

- **A paid Apple Developer Program membership.** Enrolment can take up to 48
  hours.
- **An APNs key from the same team that signs the app,** configured on your
  trackside server. A key can only push to its own team's apps, so a build
  signed by your team needs a server with your team's key.
- **The server's `APNS_BUNDLE_IDS`** set to your app's bundle ID.

The server's
[iOS Live Activities guide](https://github.com/carbonarok/trackside/blob/main/docs/ios-live-activities.md)
walks through creating the key and checking it works.

Builds run from Xcode get sandbox push tokens and TestFlight builds get
production ones. The server works out which is which, so both work against
the same server.

## How it fits together

| | |
|---|---|
| `TrackSideIOS/Config/ServerSettings.swift` | The chosen server: its address in the App Group's defaults, the API key in the shared keychain. Compiled into the widgets too. |
| `TrackSideIOS/Networking/APIClient.swift` | REST calls to trackside's `/v1` API, with the API key. |
| `TrackSideIOS/Networking/LiveClient.swift` | The `/v1/live` WebSocket that says when a board or train changed, so the app refetches only then. |
| `TrackSideIOS/Services/JourneyTracker.swift` | Follows a journey: starts a Live Activity per leg and registers its push token with the server. |
| `TrackSideIOS/Models/ActivityAttributes.swift` | The Live Activity's data. **A copy lives in `TrackSideWidgets/`**, and the server builds the same `ContentState` for its pushes. Change all three together: iOS silently ignores a push it can't decode. |
| `TrackSideWidgets/` | The departures widget and the Live Activity views. |

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `com.apple.ActivityKit.ActivityInput error 0` in the console | The installed build has no `aps-environment` entitlement, so it can't get a push token. Check the Push Notifications capability is on, then **Product → Clean Build Folder** and reinstall. |
| The server sees Live Activities ended but never registered | The same: no push token, so nothing to register. |
| Registration gets `403` | The server's `APNS_BUNDLE_IDS` doesn't include your bundle ID. |
| Registration gets `503` | The server has no APNs key. Everything else works; Live Activities just update only while the app is open. |
| Xcode won't sign: App Group or bundle ID unavailable | Someone else has that prefix. Choose another `BUNDLE_ID_PREFIX`. |
| A change you made doesn't seem to be on the phone | If Xcode asked about a file changed on disk, choose **Read From Disk**, then clean and rebuild. |
| "This server needs an API key" | The server was started with `API_KEY`. Ask whoever runs it for the key. |
| The widget says to set up a server | Open the app once and connect to a server. |

## Contributing

Pull requests are welcome. Please keep your team ID and bundle prefix in
`Config/Local.xcconfig`, out of the project file, and never commit signing
keys or `.p8` files (they're in `.gitignore`).

## Licence

[MIT](LICENSE). Train data comes from the server you connect to, under its
data providers' terms: Network Rail open data under the Open Government
Licence, and Darwin, powered by National Rail Enquiries.
