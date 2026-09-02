# Little Dia

Tap **Share** on anything — a post in X, a product page in Safari, an article —
and pick **Little Dia**. A sheet opens on top of the share sheet with a preview
of what you shared, a short brief written by Apple's on-device model, and a
place to ask follow-up questions. The content never goes to a cloud model.

The UI follows the "Dia for iOS" Figma file (Share Sheet Extensions frames):
outer sheet chrome with close / title / bookmark, a white inner sheet with a
dashed content area, the preview card, "Summarized for you by Dia" + icon-led
sections, an inline conversation, and the floating "Ask anything..." composer.

## What's here

| Target | Kind | Role |
| --- | --- | --- |
| `ShareExperiment` (displayed as *Little Dia*) | iOS app | Thin host. Installs the extension, shows whether the on-device model is usable, and lets you rehearse the flow with any URL (optionally with canned sample answers for design review). Also carries the mic probe diagnostic. |
| `ShareExtension` | Share extension | The real thing: receives the shared URL/text, resolves it, summarizes it and chats about it inside the share sheet. |
| `Shared/` | — | Compiled into both targets: `LinkResolver` + `PostEnricher` (fetching), `LinkPreview` (model), `Brief` (`@Generable` summary schema), `ChatModel` (session + streaming), `DictationController`, and the SwiftUI views (`DiaSheetView`, `InnerSheetView`, `LinkPreviewCard`, `BriefView`, `ConversationView`, `ComposerBar`, `DiaTheme`). |
| `Resources/` | — | Asset catalog: the Dia mark (vector PDF exported from Figma) and the app icon. |

## Build & run

```sh
brew install xcodegen          # if you don't have it
xcodegen generate              # regenerates ShareExperiment.xcodeproj (gitignored)
open ShareExperiment.xcodeproj
```

Run the **ShareExperiment** scheme once on a device or simulator so iOS registers
the extension. Then: open X or Safari → Share → **Little Dia**.

Console self-test (resolver output for a tweet, a product page and an article,
then a brief + one follow-up):

```sh
xcrun simctl launch --console-pty booted com.jonasleupe.ShareExperiment -selftest
xcrun simctl launch --console-pty booted com.jonasleupe.ShareExperiment -selftest -url https://example.com/some-page
```

## How the data flows

1. **Share sheet payload** → `SharedContentLoader` pulls the URL (and any text) out
   of the `NSItemProvider`s.
2. **Resolve** (`LinkResolver`, the only network code, all free and keyless):
   - X / Twitter permalinks: x.com is behind a login wall, so the post is read
     from the community tweet-JSON mirrors (`api.fxtwitter.com`, then
     `api.vxtwitter.com`): text, author, avatar, date, first photo, quoted post.
   - Everything else: the page's own HTML is fetched (≤1.5 MB, 8 s timeout) and
     parsed without WebKit: `<title>`, Open Graph / Twitter card meta, favicon
     `<link>`s, JSON-LD `Product` (name, price, brand), plus readable body text
     (chrome stripped, capped at ~3,500 chars for the model's ~4k-token window).
   - Favicons come from the page's `<link rel=icon>` or `/favicon.ico`; no
     third-party favicon services.
3. **Brief** (`ChatModel.summarize`): one `LanguageModelSession` is created with
   the resolved content as instructions, and `Brief` (summary + 1–3 sections,
   each with a title, body, icon and optional link) is streamed with guided
   generation so the summary appears word by word.
4. **Chat**: follow-ups reuse the same session, so the brief stays in context.
   Each reply shows "Thought for Ns". When the context window fills up the sheet
   offers **Start over**, which rebuilds the session with the brief as context.
5. **Dictation** (`DictationController`): the mic button records through
   `AVAudioEngine` and transcribes with `SFSpeechRecognizer`, on device where the
   locale supports it. Whether a share extension may open the microphone on
   hardware is still the open question the **Mic probe** in the host app answers.

## Constraints

- **Apple Intelligence required.** On Simulator the model reports "available" but
  generation only works if Apple Intelligence is enabled on the host Mac
  (System Settings → Apple Intelligence & Siri). The sheet shows the exact
  reason instead of failing silently. Use the host app's *Use sample answers*
  toggle to review the design without a working model.
- **~4k-token context window / ~3B model.** Body text is capped; the brief is
  short by design.
- **Extension memory budget (~120 MB).** Page bytes are capped and images are
  loaded lazily by `AsyncImage`.
- **If the sheet is dismissed, you're gone.** Nothing is persisted; the bookmark
  button is visual for now.
