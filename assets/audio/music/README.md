# Music Assets

Gameplay background music goes in `assets/audio/music/gameplay/`.

Drop `.mp3` files into that folder and `AudioManager` will discover them at runtime, shuffle them, and play them during matches. No code changes are needed for new gameplay tracks.

The generated ambient music in `AudioManager` is the menu and fallback music.
