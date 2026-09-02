# Little Dia

**A browser that comes to where you already are.** Tap Share on anything on
iOS — a post in X, a product page in Safari, an article — and pick *Little Dia*.
A sheet opens on top of the share sheet with a preview of what you shared, a
short brief written by Apple's on-device model, and a place to ask follow-up
questions. Nothing leaves your device unless you opt in to web search.

> **Now:** you tap share → press Grok/Claude/GPT → it opens a different app
> with the URL in the input field → you add a prompt and press enter → you read
> the result.
>
> **What it could be:** you tap share → tap *Little Dia* and get the insights
> right at your fingertips. It fetches the content, analyses it for you and
> gives you a helpful TL;DR plus context. If you want to learn more, you just
> ask a follow-up.

<p align="center">
  <img src="Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="96" alt="Little Dia icon">
</p>

## Why this exists

This is one of two prototypes from a 48-hour deep dive into what Dia could be
on mobile, built in the open for The Browser Company's AI Prototyper Residency.
The whole build was live-tweeted:
[the thread on X](https://x.com/jonasleupe/thread/2094707380084715579).

The thinking behind it, in short:

- A browser is mostly a GUI to navigate the web. It helps us find answers,
  connect with people, build businesses and get entertained — but it is a
  user-heavy interface that makes us type, click and double-check.
- On a phone, people open a browser for very specific moments. Looking at my
  own recent tabs: a second-hand bike, robot vacuum cleaners, a pricing page —
  most of them redirects from a chat with an AI assistant. Scrolling X, I see
  a [Matic](https://maticrobots.com) vacuum, think "that would really uplift my
  life", close X, open a chat app to ask about alternatives, then paste a link
  into Safari to find retailers and prices.
- Instead of bringing the user to the browser, **bring the browser to where the
  user already is.** Two paths came out of that: Dia embedded in the share
  sheet (this repo) and Dia embedded in the keyboard.
- The bar for every experiment: articulate the *why*, start with *what could
  be*, and make people feel something.

Before designing the visual layer, the share-sheet idea was tested first: a
custom SwiftUI surface inside a share extension is possible (mymind's share
confirmation was the closest reference), so the design could be built for
real. The Figma frames this implements live in the "Dia for iOS" file.

## What it does

1. **Preview card.** X posts show avatar, name, date, text and media. Other
   pages show an Open Graph card with image, title, description, favicon, site
   and price when the page is a product.
2. **"Summarized for you by Dia."** A one-paragraph summary plus one to three
   icon-led sections (where to buy it, what reviewers say, key facts, people,
   dates, places), streamed word by word from Apple's on-device model.
3. **Ask anything.** Follow-up questions in the same sheet, with the brief in
   context. Replies show "Thought for Ns" with a shimmering thinking state
   while the model works.
4. **Dictation.** The mic button transcribes on device.
5. **Optional web search.** Save an OpenRouter API key in the host app and
   follow-up questions go to GPT-5.6 Luna with web search instead. The summary
   still comes from Apple Intelligence on device.

## Build & run

Requirements: Xcode 26, iOS 26, an Apple-Intelligence-eligible device (or a
Mac with Apple Intelligence enabled for the simulator), and
[xcodegen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate              # regenerates ShareExperiment.xcodeproj (gitignored)
open ShareExperiment.xcodeproj
```

Set your own development team in Xcode (Signing & Capabilities) or in
`project.yml`, then run the **ShareExperiment** scheme once so iOS registers
the extension. Then: open X or Safari → Share → **Little Dia**.

The host app also lets you rehearse the flow with any URL, has a
"Use sample answers" toggle to review the design on machines without Apple
Intelligence, and a microphone probe for checking the audio path.

Console self-test (resolver output for a tweet, a product page and an article,
then a brief and one follow-up):

```sh
xcrun simctl launch --console-pty booted com.jonasleupe.ShareExperiment -selftest
xcrun simctl launch --console-pty booted com.jonasleupe.ShareExperiment -selftest -url https://example.com/some-page
```

## How it works

| Target | Role |
| --- | --- |
| `ShareExperiment` (displayed as *Little Dia*) | Thin host app: installs the extension, reports on-device model availability, holds the optional OpenRouter key, rehearsal and diagnostics. |
| `ShareExtension` | The share extension: receives the shared URL/text, resolves it, summarizes it and chats about it inside the share sheet. |
| `Shared/` | Compiled into both: `LinkResolver` + `PostEnricher` (fetching), `LinkPreview` (model), `Brief` (`@Generable` summary schema), `ChatModel` (session + streaming), `OpenRouterClient` + `OpenRouterKeyStore` (optional web search), `DictationController`, and the SwiftUI views (`DiaSheetView`, `InnerSheetView`, `LinkPreviewCard`, `BriefView`, `ConversationView`, `ComposerBar`, `DiaTheme`). |
| `Resources/` | Asset catalog: the Dia mark (vector) and the app icon. |

Data flow:

1. **Share sheet payload** → `SharedContentLoader` pulls the URL (and any text)
   out of the `NSItemProvider`s.
2. **Resolve** (`LinkResolver`, free and keyless):
   - X / Twitter permalinks are behind a login wall, so the post is read from
     the community tweet-JSON mirrors (`api.fxtwitter.com`, then
     `api.vxtwitter.com`): text, author, avatar, date, first photo, quoted post.
   - Everything else: the page's own HTML is fetched (≤1.5 MB, 8 s timeout) and
     parsed without WebKit: `<title>`, Open Graph / Twitter card meta, favicon
     `<link>`s, JSON-LD `Product` (name, price, brand), plus readable body text
     capped at ~3,500 characters for the model's ~4k-token window.
   - Favicons come from the page's `<link rel=icon>` or `/favicon.ico`.
3. **Brief** (`ChatModel.summarize`): one `LanguageModelSession` is created with
   the resolved content as instructions and `Brief` is streamed with guided
   generation so the summary appears word by word.
4. **Chat**: follow-ups reuse the same session. When the context window fills
   up the sheet offers **Start over**, which rebuilds the session with the brief
   as context.
5. **Web search (optional)**: the OpenRouter key is stored in the Keychain
   inside the `group.com.jonasleupe.ShareExperiment` App Group so the extension
   can read it. With a key present, follow-ups stream from
   `openai/gpt-5.6-luna` with OpenRouter's `web` plugin ("Searched the web for
   Ns"); the shared content, the brief and the conversation are sent to
   OpenRouter for those. If Apple Intelligence is unavailable altogether, the
   web model writes the sections instead. Remove the key to go back to
   on-device only. **No key is stored in this repository.**
6. **Dictation** (`DictationController`): `AVAudioEngine` + `SFSpeechRecognizer`,
   on device where the locale supports it.

## Constraints and open questions

- **Apple Intelligence required** for the on-device brief. On Simulator,
  generation only works if Apple Intelligence is enabled on the host Mac.
- **~4k-token context window / ~3B model.** Body text is capped; the brief is
  short by design.
- **Extension memory budget (~120 MB).** Page bytes are capped and images are
  loaded lazily.
- **Microphone inside a share extension** on hardware is still the open
  question the mic probe in the host app answers.
- **Nothing is persisted.** If the sheet is dismissed, the conversation is
  gone; the bookmark button is visual for now.

## Credits

Design and concept by [Jonas Leupe](https://jonasleupe.com). Dia and the Dia
mark belong to The Browser Company; this is an independent exploration and a
love letter, not an official product.
