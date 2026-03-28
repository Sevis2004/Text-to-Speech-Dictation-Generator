\# Text-to-Speech-Dictation-Generator



\## Overview

This project generates high-quality audio dictations (MP3) from text using a Text-to-Speech (TTS) engine.



It was designed as an automated pipeline to convert structured text into ready-to-use audio files with natural pauses and formatting.



\---



\## Key Features

\- Convert text into speech (MP3)

\- Automatic pause handling for dictation-style audio

\- Batch processing of multiple texts

\- Clean output ready for publishing

\- Optional HTML generation for playback



\---

\---

\## Setup

This project requires API credentials for TTS and storage services.

For security reasons, credentials are not included in the repository.

To run the project:
\1. Create a TTS API account (e.g. Yandex SpeechKit)
\2. Add your API key to configuration
\3. Run the main script

Alternatively, see the live demo above for example output.

\---

\## Tech Stack

\- PowerShell (main pipeline)

\- Yandex SpeechKit TTS

\- ffmpeg (audio processing)


## Architecture 

generate_dictations.ps1 — general script
- `test_split.ps1 — test splitting sentenses (legacy vs improved)`
- `index.template.html — template of start page (mp3 player`
- `dictations.json — data`
- `dictations.txt - texts for generate speech`
- `two algoritm for split sentenses legacy an improved (used now)`


\---



## Demo

Live demo (recommended):
https://website.yandexcloud.net/dictation-audio/

Example output files:
- `output/osen_full.mp3`
- `output/index.html`


\---



\## How It Works

1\. Input text is structured and split into segments

2\. Each segment is sent to TTS API

3\. Audio parts are generated and processed

4\. Final MP3 is assembled using ffmpeg

5\. (Optional) Files are prepared for publishing



\---



\## Configuration

\- Requires API access to a TTS provider (Yandex SpeechKit used by default)

\- Can be adapted to other TTS services



\---



\## Notes

\- Yandex TTS is a paid service (free credits may apply)

\- The architecture allows replacing TTS provider if needed



\---



\## Use Cases

\- Educational content

\- Language learning materials

\- Automated voice content generation

\- Dictation systems



\---



\## Author

Automation / scripting project focused on real-world workflow optimization.
