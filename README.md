# Dhol

**Speak, and it types.**

Dhol is a dictation app that lives in your Mac's menu bar. Hold a shortcut,
say what you want, let go — the words appear in whatever you were already
using: a terminal, an editor, a browser, a chat box, a search field.

Everything happens on your Mac. Your voice is never uploaded, never stored,
and never sent to anyone. There is no account, no subscription, and no
network connection needed once the app is set up.

## Install

1. Download the latest `Dhol.zip` from the
   [Releases page](https://github.com/steelbrain/dhol.app/releases).
2. Unzip it and drag **Dhol.app** into your **Applications** folder.
3. Open it. The app is signed and notarized by Apple, so it opens normally —
   no scary warnings, no right-click tricks.

You'll need an Apple silicon Mac (M1 or newer) running macOS 14 Sonoma or
later, and about 2.4 GB of free disk space.

**First launch takes a few minutes.** Dhol downloads its speech recognition
model once, then never phones home again. The menu bar will say "Downloading"
while it works. There's no percentage — the download doesn't report one, and
a made-up number would be worse than none.

## Set it up

Open **Settings** from the menu bar icon and grant two permissions:

- **Microphone** — so Dhol can hear you.
- **Accessibility** — so Dhol can type for you.

Both have a button right there in the Permissions section. You only grant
them once.

While you're in Settings, turn on **Start at login** so Dhol is always ready.
(Move the app to `/Applications` first, or macOS won't remember it.)

## Use it

**Hold ⌥Space, speak, let go.** That's the whole thing.

- Words appear as you talk, about a second behind your voice.
- When you let go, Dhol takes one last listen at the full recording and fixes
  anything it got wrong mid-sentence.
- The menu bar icon turns red while it's listening.
- Want a different shortcut? Change it in Settings — click the shortcut field
  and press the keys you want.

A few things worth knowing:

- Dhol only ever deletes text it typed itself. If you start typing or click
  somewhere in the middle of a dictation, it stops correcting rather than risk
  touching your work.
- Longer dictations show live text a little further behind, but the final
  result is just as accurate.
- It works in every app, because it sends real keystrokes. There's no list of
  supported apps to check.
- It understands 25 languages and adds punctuation and capitalization on its
  own.

## If something goes wrong

**Nothing is typed.** Check that Accessibility is granted in Settings. macOS
sometimes needs the app removed and re-added after an update.

**It doesn't hear you.** Check Microphone in Settings, and check that the
right input device is selected in System Settings → Sound.

**It won't start at login.** Make sure Dhol is in `/Applications`, then toggle
the setting off and on. If macOS asks for approval, the Settings window will
show an **Approve…** button.

**Something else.** Dhol writes failures to the system log:

```sh
/usr/bin/log stream --predicate 'subsystem == "ai.aneesiqbal.dhol"'
```

(If you're in zsh, use the full `/usr/bin/log` path — plain `log` is a shell
builtin.)

Still stuck? [Open an issue](https://github.com/steelbrain/dhol.app/issues)
and include what you saw.

## Privacy

Dhol records only while you hold the shortcut. Audio stays in memory, is
transcribed on your own machine, and is thrown away when the dictation ends.
Nothing is written to disk, and nothing is sent over the network. The one
exception is the initial model download on first launch.

---

## For developers

Dhol is MIT licensed and open source. Contributions are welcome.

**Requirements:** Apple silicon, macOS 14+, a full Xcode installation (MLX's
Metal shaders can't be built by command-line SwiftPM alone), and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
./Scripts/build-app.sh
open build/Dhol.app
```

`Dhol.xcodeproj` and `Sources/DholApp/Resources/Info.plist` are generated and
not committed. `project.yml` is the source of truth for targets, build
settings, bundle keys and Swift package dependencies, which Xcode resolves and
pins into `Package.resolved`. The version lives there too, as
`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.

```sh
./Scripts/generate-project.sh   # after changing project.yml, or on a fresh clone
open Dhol.xcodeproj
xcodebuild -project Dhol.xcodeproj -scheme Dhol test
```

Local builds are signed with an Apple Development certificate, so the app's
identity survives a rebuild and the two permissions only have to be granted
once.

### How it works

While you hold the shortcut, Dhol re-transcribes the whole recording every
half second and types the words that two consecutive passes agree on, so text
lands about a second behind your voice. Waiting for that agreement is the
point: a hypothesis that is still changing would have to be typed and then
taken back.

Because every pass decodes the whole recording, passes get slower as a
dictation gets longer and live text falls further behind. The loop just ticks
less often; the final pass is unaffected.

Releasing the shortcut runs one final pass over the entire recording. Because
that pass hears everything at once it can disagree with the live ones, so Dhol
deletes the part that changed and retypes it. It only ever deletes characters
it typed itself, and if you type or click mid-dictation it stops correcting
altogether rather than risk eating your own input.

Text goes in as synthesised keystrokes, which is the one thing every target
understands the same way. There is no list of supported apps.

### Model and licensing

The app is MIT licensed. Speech recognition uses
`mlx-community/parakeet-tdt-0.6b-v3`, an MLX conversion of NVIDIA's Parakeet
TDT 0.6B v3: 25 languages, with punctuation and capitalization. NVIDIA's
original model and the converted weights are CC BY 4.0 and are downloaded
separately — they are not vendored here.

If you swap the model, check its `vocab.txt` first: several Parakeet variants
have no punctuation or capital letters in their vocabulary at all, and no
amount of post-processing recovers what the model cannot emit.

---

Made by Anees Iqbal — <https://github.com/steelbrain/dhol.app>
