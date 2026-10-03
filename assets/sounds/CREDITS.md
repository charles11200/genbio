# Sound effect sources

The three short SFX (`start.mp3`, `win.wav`, `lose.mp3`) are from
[Mixkit](https://mixkit.co), under the **Mixkit Sound Effects Free
License**: free for personal and commercial use, no attribution required.
The only restriction is reselling a file unaltered as a standalone asset -
using it as one embedded sound inside a compiled app (this project) is
standard permitted use. Full terms: https://mixkit.co/license/

`bgm.mp3` (the looping background track, see
`lib/services/sound_service.dart`) is deliberately **not** from Mixkit -
Mixkit's separate *Stock Music* license (as opposed to the Sound Effects
license above) explicitly excludes video games from permitted use. It's
from [Pixabay](https://pixabay.com) instead, under the **Pixabay Content
License**: royalty-free for commercial and non-commercial use, no
attribution required, no video-game exclusion - the only restriction is
reselling/redistributing the audio file itself unaltered as a standalone
product, same shape of restriction as Mixkit's, just without the carve-out
that would rule this project out. Full terms:
https://pixabay.com/service/terms/

Not bundled into the app itself (not listed in pubspec.yaml's `assets:`) -
this file is documentation only, kept for the record in case sourcing is
ever questioned (e.g. during a thesis defense).

| File | Source item | Source page | Direct file |
|---|---|---|---|
| `start.mp3` | Mixkit "Unlock game notification" (id 253) | https://mixkit.co/free-sound-effects/game/ | https://assets.mixkit.co/active_storage/sfx/253/253-preview.mp3 |
| `win.wav` | Mixkit "Winning notification" (id 2018) | https://mixkit.co/free-sound-effects/win/ | https://assets.mixkit.co/active_storage/sfx/2018/2018.wav |
| `lose.mp3` | Mixkit "Losing piano" (id 2024) | https://mixkit.co/free-sound-effects/lose/ | https://assets.mixkit.co/active_storage/sfx/2024/2024-preview.mp3 |
| `bgm.mp3` | Pixabay "Quiz Countdown - Thinking Time" by Sonican | https://pixabay.com/music/corporate-quiz-countdown-thinking-time-238530/ | https://cdn.pixabay.com/download/audio/2024/09/06/audio_b9a7cf1826.mp3 |

`lose.mp3` was chosen over Mixkit's buzzer/wrong-answer alternatives
deliberately - a short, soft descending piano phrase reads as a neutral
"try again" for a student in a formative-assessment app, rather than a
harsh game-show-style fail sound.

`bgm.mp3` was picked specifically because Pixabay tags it for quiz/trivia
use - light, instrumental, no vocals, loops without an awkward seam. If it
doesn't feel right once you've heard it in the app, swapping it is a
one-file change - see the note in `SoundService`.
