
import logging
logging.getLogger("moderngl_window").setLevel(logging.WARNING)
logging.getLogger("moderngl_window.context.base.window").setLevel(logging.WARNING)
logging.getLogger("moderngl_window.context.pyglet").setLevel(logging.WARNING)

from dotenv import load_dotenv
load_dotenv()

import os
import threading
import numpy as np
import platform

from dataclasses import dataclass, field
from collections import deque

import moderngl
import moderngl_window as mglw
from PIL import Image, ImageDraw, ImageFont

ROUTER = "BlackHole 2ch"
GAIN = 1.7

"""
TODO:

Idle detection + animation + audio free
audio free button
spotifiy interaction ui + buttons
song cover animation
lyric display
js texts

"""

# ── Shared State ─────────────────────────────────────────────────────────────

@dataclass
class AppState:
    fft_data:    np.ndarray       = field(default_factory=lambda: np.zeros(512))
    fft_lock:    threading.Lock   = field(default_factory=threading.Lock)
    stop_event:  threading.Event  = field(default_factory=threading.Event)
    track_name:  str = ""
    artist:      str = ""
    album:       str = ""
    track_id:    str = ""
    bpm:         float = 120.0
    spotify_volume: int = 50
    duration_ms: int = 0
    progress_ms: int = 0

    next_track_name:  str = ""
    next_artist:      str = ""
    next_album:       str = ""

    song_skip: bool = True

    # Steuerung
    stop_event: threading.Event = field(default_factory=threading.Event)

    def __str__(self):
        return f"Title: {self.track_name} by {self.artist}"


# ── Audio Thread ──────────────────────────────────────────────────────────────

class SystemDeviceManager:
    def __init__(self):
        import sounddevice as sd

        self.audio_switch_path = os.path.join(os.path.dirname(os.path.realpath(__file__)), "SwitchAudio")
        self.all_devices = sd.query_devices()

        default_output_index = sd.default.device[1]
        if default_output_index is not None:
            self.default_device_name = sd.query_devices(default_output_index)["name"]

        self.set_system_output_device(ROUTER)

    def set_system_output_device(self, name):
        import subprocess
        subprocess.run([self.audio_switch_path, "output", name], check=False)

    def __del__(self):
        if self.default_device_name:
            self.set_system_output_device(self.default_device_name)


def start_audio_thread(state: AppState, output_device_name: str) -> threading.Thread:
    from scipy.signal import windows
    import sounddevice as sd

    def get_device_index(name):
        devices = sd.query_devices()
        return next(i for i, d in enumerate(devices) if name in d["name"])

    # Find BlackHole input and a valid output device for instant replay
    black_hole_index = get_device_index(ROUTER)
    out_index = get_device_index(output_device_name)
    print("Playing on: ", output_device_name, out_index)

    CHUNK = 2048
    SR = 44100
    hann = windows.hann(CHUNK)
    raw_buffer = deque(maxlen=CHUNK)

    def audio_callback(indata, outdata, frames, time, status):
        raw_buffer.extend(indata[:, 0])
        if len(raw_buffer) >= CHUNK:
            chunk = np.array(raw_buffer)
            spectrum = np.abs(np.fft.rfft(chunk * hann))[:512]
            log_spec = np.log1p(spectrum)
            normalized = log_spec / (log_spec.max() + 1e-8)
            with state.fft_lock:
                state.fft_data[:] = state.fft_data * 0.7 + normalized * 0.3
        out = indata * GAIN
        out = np.clip(out, -1.0, 1.0)
        outdata[:] = out

    def run():
        with sd.Stream(
            device=(black_hole_index, out_index),
            samplerate=SR,
            blocksize=1024,
            channels=2,
            callback=audio_callback,
        ):
            state.stop_event.wait()

    t = threading.Thread(target=run, daemon=True, name="audio")
    t.start()
    return t


# ── Spotify Thread ────────────────────────────────────────────────────────────

def start_spotify_thread(state: AppState) -> threading.Thread:
    import spotipy
    from spotipy.oauth2 import SpotifyOAuth

    try:
        sp = spotipy.Spotify(auth_manager=SpotifyOAuth(
            scope="user-read-playback-state user-modify-playback-state",
            cache_path=".spotify_cache",
        ))
    except:
        print("Spotify failed")

    def run():
        while not state.stop_event.is_set():
            try:
                pb = sp.current_playback()
                if pb and pb["is_playing"]:
                    track = pb["item"]
                    state.track_name = track["name"]
                    state.artist = track["artists"][0]["name"]
                    state.progress_ms = pb["progress_ms"]
                    state.album      = track["album"]["name"]
                    state.track_id   = track["id"]
                    state.duration_ms = track["duration_ms"]
                    # get audio features
                    try:
                        track_id = track.get("id")
                        if getattr(state, "track_id", None) != track_id:
                            state.track_id = track_id
                            af = sp.audio_features(track_id)
                            if af and af[0]:
                                state.bpm = af[0].get("tempo")
                            else:
                                state.bpm = None
                    except Exception:
                        pass
                    # get upcoming track data
                    try:
                        queue = sp.queue()
                        if queue and queue["queue"]:
                            nxt = queue["queue"][0]
                            state.next_track_name = nxt["name"]
                            state.next_artist     = nxt["artists"][0]["name"]
                            state.next_album      = nxt["album"]["name"]
                    except Exception:
                        pass
            except Exception:
                pass
            state.stop_event.wait(timeout=1.0)

    t = threading.Thread(target=run, daemon=True, name="spotify")
    t.start()
    return t


# ── Renderer ──────────────────────────────────────────────────────────────────

class Visualizer(mglw.WindowConfig):
    title = "Visualizer"
    gl_version = (4, 1)
    window_size = (1920, 1080)
    state = None

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        def get_glsl_version():
            return "410 core" if platform.system() == "Darwin" else "300 es"
        self.get_glsl_version = get_glsl_version

        base_dir = os.path.dirname(os.path.realpath(__file__))
        self.shader_dir = os.path.join(base_dir, "shaders")
        self.vert_path = os.path.join(base_dir, "vert.glsl")
        self.vert_src = self.load_file(self.vert_path)

        self.shaders = []
        self.shader_index = 0
        self.reload_shaders()

        self.time = 0

        # overlay shader (built once, never swapped)
        self.overlay_prog = self.ctx.program(
            vertex_shader=self.vert_src,
            fragment_shader=self.load_file(os.path.join(base_dir, "overlay.glsl"))
        )

        self.fft_tex = self.ctx.texture((512, 1), components=1, dtype="f4")

        # text texture: RGBA, 1920x1080, CPU-rendered via Pillow
        self.text_tex = self.ctx.texture((1920, 1080), components=4, dtype="f1")
        self.text_tex.filter = (moderngl.LINEAR, moderngl.LINEAR)

        self.quad = mglw.geometry.quad_fs()

        # overlay state
        self.overlay_active = False
        self.overlay_start  = 0.0
        self.overlay_duration = 4.0   # seconds the overlay is fully visible
        self.fade_duration    = 1.0   # seconds to fade in and out
        self.last_track_id  = None

    # ─── file loading ────────────────────────────────────────────────

    def load_file(self, path):
        with open(path, "r") as f:
            content = f.read()
        return content.format(
            glsl_version=self.get_glsl_version(),
            precision="" if platform.system() == "Darwin" else "precision highp float;"
        )

    # ─── shader management ───────────────────────────────────────────

    def reload_shaders(self):
        self.shaders = sorted([
            f for f in os.listdir(self.shader_dir)
            if f.endswith(".glsl") and not f.startswith(("vert", "overlay"))
        ])
        self.shader_index = max(0, min(self.shader_index, len(self.shaders) - 1))
        self.build_program()

    def build_program(self):
        if not self.shaders:
            return
        frag_path = os.path.join(self.shader_dir, self.shaders[self.shader_index])
        self.prog = self.ctx.program(
            vertex_shader=self.vert_src,
            fragment_shader=self.load_file(frag_path)
        )

    def next_shader(self):
        self.shader_index = (self.shader_index + 1) % len(self.shaders)
        self.build_program()

    def prev_shader(self):
        self.shader_index = (self.shader_index - 1) % len(self.shaders)
        self.build_program()

    # ─── text texture ────────────────────────────────────────────────

    def render_text_texture(self, track_name: str, artist: str, album: str):
        """CPU-render track info into an RGBA texture via Pillow."""
        img = Image.new("RGBA", (1920, 1080), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)

        try:
            font_large  = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 96)
            font_medium = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 52)
            font_small  = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 38)
        except Exception:
            font_large = font_medium = font_small = ImageFont.load_default()

        cx = 960

        # track name
        draw.text((cx, 420), track_name, font=font_large,
                  fill=(255, 255, 255, 255), anchor="mm")
        # artist
        draw.text((cx, 540), artist, font=font_medium,
                  fill=(200, 200, 220, 200), anchor="mm")
        # album
        draw.text((cx, 620), album, font=font_small,
                  fill=(140, 140, 160, 160), anchor="mm")

        # flip vertically — OpenGL's origin is bottom-left
        img = img.transpose(Image.FLIP_TOP_BOTTOM)
        self.text_tex.write(img.tobytes())

    # ─── overlay trigger ─────────────────────────────────────────────

    def should_trigger_overlay(self, time: float) -> bool:
        """Returns True when we should start the overlay fade-in."""
        progress  = self.state.progress_ms
        duration  = self.state.duration_ms
        if duration <= 0 or progress <= 0:
            return False

        remaining_ms = duration - progress
        # total overlay time = fade_in + visible + fade_out

        return remaining_ms <= 2 * 1000

    def trigger_overlay(self, time: float):
        self.overlay_active = True
        self.overlay_start  = time

    def overlay_alpha(self, time: float) -> float:
        """Returns 0.0–1.0 blend weight for the overlay."""
        if not self.overlay_active:
            return 0.0
        elapsed = time - self.overlay_start
        total   = self.overlay_duration + self.fade_duration * 2
        if elapsed > total:
            self.overlay_active = False
            self.state.song_skip = False
            return 0.0
        if elapsed < self.fade_duration:
            if self.state.song_skip:
                return 1.0
            return elapsed / self.fade_duration # fade in
        if elapsed < self.fade_duration + self.overlay_duration:
            return 1.0                                                  # full
        return 1.0 - (elapsed - self.fade_duration - self.overlay_duration) / self.fade_duration  # fade out

    def get_next_track_info(self):
        name   = self.state.next_track_name or self.state.track_name
        artist = self.state.next_artist     or self.state.artist
        album  = self.state.next_album      or self.state.album
        return name, artist, album

    # ─── uniforms ────────────────────────────────────────────────────

    def set_uniform(self, prog, name, value):
        if name in prog:
            prog[name] = value

    # ─── render loop ─────────────────────────────────────────────────

    def render(self, time: float, frame_time: float):
        self.time = time
        self.ctx.clear()

        track_id = getattr(self.state, "track_id", None)

        # ── anticipate transition ─────────────────────────────────────
        if not self.overlay_active and self.should_trigger_overlay(time):
            # pre-fetch next track info if available
            next_name, next_artist, next_album = self.get_next_track_info()
            self.render_text_texture(next_name, next_artist, next_album)
            self.trigger_overlay(time)
            # remember we already triggered for this track
            self.last_track_id = track_id

        # ── react to actual track change (fallback + update text) ────
        elif track_id and track_id != self.last_track_id:
            self.state.song_skip = True
            self.last_track_id = track_id
            if not self.overlay_active:
                # song changed without anticipation (e.g. manual skip)
                self.render_text_texture(
                    self.state.track_name,
                    self.state.artist,
                    getattr(self.state, "album", ""),
                )
                self.trigger_overlay(time)

        # upload FFT
        with self.state.fft_lock:
            fft_copy = self.state.fft_data.astype("f4")
        self.fft_tex.write(fft_copy.tobytes())

        alpha = self.overlay_alpha(time)

        if alpha < 0.001:
            # ── main shader only ──────────────────────────────────────
            self.fft_tex.use(location=0)
            self.set_uniform(self.prog, "iFFT",  0)
            self.set_uniform(self.prog, "iTime", time)
            self.set_uniform(self.prog, "iBPM",  self.state.bpm)
            self.set_uniform(self.prog, "iRes",  tuple(self.wnd.size))
            self.quad.render(self.prog)

        elif alpha > 0.999:
            # ── overlay only ──────────────────────────────────────────
            self.fft_tex.use(location=0)
            self.text_tex.use(location=1)
            self.set_uniform(self.overlay_prog, "iFFT",    0)
            self.set_uniform(self.overlay_prog, "iText",   1)
            self.set_uniform(self.overlay_prog, "iTime",   time)
            self.set_uniform(self.overlay_prog, "iAlpha",  1.0)
            self.set_uniform(self.overlay_prog, "iRes",    tuple(self.wnd.size))
            self.quad.render(self.overlay_prog)

        else:
            # ── blend: render main → FBO, overlay on top with alpha ───
            # simple approach: render main first, then overlay blended on top
            self.ctx.enable(moderngl.BLEND)
            self.ctx.blend_func = moderngl.SRC_ALPHA, moderngl.ONE_MINUS_SRC_ALPHA

            self.fft_tex.use(location=0)
            self.set_uniform(self.prog, "iFFT",  0)
            self.set_uniform(self.prog, "iTime", time)
            self.set_uniform(self.prog, "iBPM",  self.state.bpm)
            self.set_uniform(self.prog, "iRes",  tuple(self.wnd.size))
            self.quad.render(self.prog)

            self.fft_tex.use(location=0)
            self.text_tex.use(location=1)
            self.set_uniform(self.overlay_prog, "iFFT",   0)
            self.set_uniform(self.overlay_prog, "iText",  1)
            self.set_uniform(self.overlay_prog, "iTime",  time)
            self.set_uniform(self.overlay_prog, "iAlpha", alpha)
            self.set_uniform(self.overlay_prog, "iRes",   tuple(self.wnd.size))
            self.quad.render(self.overlay_prog)

            self.ctx.disable(moderngl.BLEND)

    # ─── input ───────────────────────────────────────────────────────

    def key_event(self, key, action, modifiers):
        if action != self.wnd.keys.ACTION_PRESS:
            return
        if key == self.wnd.keys.ESCAPE:
            self.state.stop_event.set()
            self.wnd.close()
        # info
        elif key == self.wnd.keys.I:
            print(self.state)
        # shader control
        elif key == self.wnd.keys.Q:
            self.prev_shader()
        elif key == self.wnd.keys.E:
            self.next_shader()
        elif key == self.wnd.keys.R:
            self.reload_shaders()
        elif key == self.wnd.keys.O:
            self.state.song_skip = True
            self.trigger_overlay(self.time)  # manual trigger for testing

# ── Einstiegspunkt ────────────────────────────────────────────────────────────

def main():
    state = AppState()

    sdm = SystemDeviceManager()

    # Threads starten
    audio_thread = start_audio_thread(state, sdm.default_device_name)
    spotify_thread = start_spotify_thread(state)

    # Renderer bekommt Zugriff auf State (Klassenattribut als DI)
    Visualizer.state = state

    try:
        mglw.run_window_config(Visualizer)
    except KeyboardInterrupt:
        pass
    finally:
        state.stop_event.set()
        audio_thread.join(timeout=2)
        spotify_thread.join(timeout=2)


if __name__ == "__main__":
    main()