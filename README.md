# ReelProof personal iPhone app

The personal-device iPhone/iPad IPA compiled successfully on macOS with Xcode 16.4. The app and ReplayKit extension are both version 0.4.1 (4).

- [Download personal-test IPA](https://reelproof-mobile.vercel.app/downloads/reelproof-ios-personal.ipa)
- [Windows signing and installation guide](https://reelproof-mobile.vercel.app/ios-personal.html)
- [Successful build and artifact](https://github.com/nambu6322-gif/comsci/actions/runs/39358809587)
- [Source](reelproof-personal/)

The IPA requires development re-signing with your own Apple account on Windows, for example using Sideloadly, before installation. It is not a TestFlight build or a directly installable download. Free personal provisioning usually needs refreshing after 7 days. Actual iPhone capture, notifications and latency have not been device-tested.

Gemini API keys belong only in the evidence server's secret settings. The app uses a separately issued server access token. Without it, only the experimental on-device text-style signal runs. That signal does not establish the video's AI origin or claim truth; the current FEVER corpus contains two documents.

## Rebuild

Actions → **Build personal iPhone IPA for Windows signing** → **Run workflow**. The macOS build requires no Apple login or Gemini key. After a successful run, download the artifact and re-sign its IPA on your own computer.

IPA SHA-256: `2a28ff8ec1a7c9635dc68a9175b9ee5fdad4eac9893680b9d7f376c42350397c`
